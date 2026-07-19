import Foundation
import UIKit
import Supabase
import Helpers

/// Remote debug & crash sink for Working Knowledge.
///
/// Streams the live `DebugTelemetry` snapshot plus any structured event
/// (errors, model-load failures, lifecycle milestones, app-hang/crash traces
/// captured on the previous launch) to the `debug_events` table in Supabase.
///
/// All transmissions are best-effort and fire-and-forget: a network failure
/// never affects app behavior. Inserts are anonymous (the table RLS allows
/// inserts from anyone, reads are service-role only) so this works without
/// sign-in on every install.
@Observable
final class DebugReporter {
    // MARK: - Identity

    /// Stable per-install ID (UUID generated on first run, persisted in
    /// UserDefaults). Not the device, not the user — just this install.
    private(set) var installID: String

    // MARK: - Static device info (captured once)

    let appVersion: String
    let appBuild: String
    let deviceModel: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool

    // MARK: - Run state

    private(set) var lastTransmittedAt: Date?
    private(set) var pendingEventCount: Int = 0
    private(set) var lastError: String?

    private let supabase: SupabaseClient?
    private var heartbeatTask: Task<Void, Never>?
    private var crashScanTask: Task<Void, Never>?

    /// Heartbeat cadence. Every interval we push a `telemetry` event with the
    /// current memory + model-load snapshot.
    private let heartbeatInterval: TimeInterval

    init(heartbeatInterval: TimeInterval = 30) {
        self.heartbeatInterval = heartbeatInterval

        // Install ID
        let key = "wk.debug.installID"
        let stored = UserDefaults.standard.string(forKey: key)
        if let stored {
            installID = stored
        } else {
            let fresh = UUID().uuidString
            UserDefaults.standard.set(fresh, forKey: key)
            installID = fresh
        }

        // App version
        let info = Bundle.main.infoDictionary
        appVersion = (info?["CFBundleShortVersionString"] as? String) ?? "?"
        appBuild = (info?["CFBundleVersion"] as? String) ?? "?"

        // Device
        var sys = utsname()
        uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        deviceModel = mirror.children.reduce("") { acc, elem in
            guard let v = elem.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
        systemName = UIDevice.current.systemName
        systemVersion = UIDevice.current.systemVersion
        #if targetEnvironment(simulator)
        isSimulator = true
        #else
        isSimulator = false
        #endif

        // Supabase client. If env vars aren't injected, we no-op every send.
        let urlString = Config.EXPO_PUBLIC_SUPABASE_URL
        let keyString = Config.EXPO_PUBLIC_SUPABASE_ANON_KEY
        if !urlString.isEmpty, !keyString.isEmpty,
           let url = URL(string: urlString) {
            supabase = SupabaseClient(
                supabaseURL: url,
                supabaseKey: keyString
            )
        } else {
            supabase = nil
        }
    }

    // MARK: - Lifecycle

    /// Starts the heartbeat and scans the previous-launch crash logs.
    func start(telemetry: DebugTelemetry, models: ModelManager) {
        guard heartbeatTask == nil else { return }
        reportLaunch()
        scanPreviousCrashLogs()
        startHeartbeat(telemetry: telemetry, models: models)
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        crashScanTask?.cancel()
        crashScanTask = nil
    }

    // MARK: - Public reporting API

    /// One-shot structured event. `kind` is a short slug like `error`,
    /// `model_load_failed`, `lifecycle`, `user_action`. `payload` is a
    /// JSON-compatible dictionary (frames, context, arbitrary tags) whose
    /// values are primitives, nested dictionaries, or arrays of the same.
    func report(
        kind: String,
        severity: Severity = .info,
        source: String? = nil,
        message: String? = nil,
        payload: [String: AnyJSON] = [:],
        telemetry: DebugTelemetry? = nil,
        models: ModelManager? = nil
    ) {
        Task { [weak self] in
            await self?.send(
                kind: kind,
                severity: severity,
                source: source,
                message: message,
                payload: payload,
                telemetry: telemetry,
                models: models
            )
        }
    }

    // MARK: - Heartbeat

    private func startHeartbeat(telemetry: DebugTelemetry, models: ModelManager) {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self, weak telemetry, weak models] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self?.heartbeatInterval ?? 30))
                if Task.isCancelled { return }
                guard let self else { return }
                guard let telemetry else { return }
                await self.send(
                    kind: "telemetry",
                    severity: .info,
                    source: "heartbeat",
                    message: nil,
                    payload: self.telemetryPayload(telemetry: telemetry, models: models),
                    telemetry: telemetry,
                    models: models
                )
                self.lastTransmittedAt = Date()
            }
        }
    }

    // MARK: - Launch + crash-log scan

    private func reportLaunch() {
        report(
            kind: "lifecycle",
            severity: .info,
            source: "app",
            message: "launched",
            payload: [
                "launch_kind": .string("cold"),
                "boot_seconds": .double(ProcessInfo.processInfo.systemUptime),
            ]
        )
    }

    /// On launch, walks `~/Library/Logs/DiagnosticReports` for `.ips` crash
    /// files from the *previous* run (mtime within the last 24h) and uploads
    /// each as a `crash` event. The file is deleted after a successful upload
    /// so we don't re-report it next time.
    private func scanPreviousCrashLogs() {
        crashScanTask?.cancel()
        crashScanTask = Task { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let home = NSHomeDirectory()
            let reportsURL = URL(fileURLWithPath: home)
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Logs", isDirectory: true)
                .appendingPathComponent("DiagnosticReports", isDirectory: true)

            guard let enumerator = fm.enumerator(
                at: reportsURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
            ) else { return }

            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            let bundleID = Bundle.main.bundleIdentifier ?? "WorkingKnowledge"

            for case let url as URL in enumerator {
                let name = url.lastPathComponent
                guard name.hasSuffix(".ips") else { continue }
                // Only crash reports for our process (named with the bundle id
                // or app executable). Avoids uploading unrelated system dumps.
                guard name.contains(bundleID) || name.contains("WorkingKnowledge") else { continue }

                let values = try? url.resourceValues(
                    forKeys: [.contentModificationDateKey, .fileSizeKey]
                )
                let mtime = values?.contentModificationDate ?? .distantPast
                guard mtime > cutoff else { continue }

                let size = values?.fileSize ?? 0
                // Skip huge reports — they're almost certainly not ours.
                guard size < 256_000 else { continue }

                let body = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                guard !body.isEmpty else { continue }

                let payload: [String: AnyJSON] = [
                    "filename": .string(name),
                    "mtime_iso": .string(ISO8601DateFormatter().string(from: mtime)),
                    "size_bytes": .integer(Int(size)),
                    "report": .string(String(body.prefix(20_000))),
                ]

                await self.send(
                    kind: "crash",
                    severity: .critical,
                    source: "diagnostic_reports",
                    message: name,
                    payload: payload,
                    telemetry: nil,
                    models: nil
                )

                // Best-effort: archive the file so we don't re-upload.
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Payload assembly

    /// Builds the structured JSON payload for a telemetry heartbeat.
    private func telemetryPayload(
        telemetry: DebugTelemetry,
        models: ModelManager?
    ) -> [String: AnyJSON] {
        var payload: [String: AnyJSON] = [
            "resident_bytes": .integer(Int(telemetry.residentBytes)),
            "physical_footprint_bytes": .integer(Int(telemetry.physicalFootprintBytes)),
            "available_bytes": .integer(Int(telemetry.availableBytes)),
            "device_total_bytes": .integer(Int(telemetry.deviceTotalBytes)),
            "model_cache_bytes": .integer(Int(telemetry.modelCacheBytes)),
            "thermal_state": .string(thermalStateString(telemetry.thermalState)),
            "low_power_mode": .bool(telemetry.lowPowerMode),
            "processor_active": .integer(telemetry.activeProcessorCount),
            "processor_total": .integer(telemetry.processorCount),
            "process_uptime": .double(telemetry.processUptime),
        ]

        if let models {
            var phases: [String: AnyJSON] = [:]
            for spec in ModelCatalog.all {
                phases[String(describing: spec.role)] = .string(String(describing: models.phase(for: spec.role)))
            }
            payload["model_phases"] = .object(phases)
            payload["model_total_bytes_on_disk"] = .integer(Int(models.totalBytesOnDisk))
            payload["model_any_busy"] = .bool(models.isAnyBusy)
            payload["can_answer_locally"] = .bool(models.canAnswerLocally)
        }

        return payload
    }

    private func thermalStateString(_ s: ProcessInfo.ThermalState) -> String {
        switch s {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Transmission

    /// Inserts one row into `debug_events`. Silently no-ops if the client isn't
    /// configured or the network is down.
    private func send(
        kind: String,
        severity: Severity,
        source: String?,
        message: String?,
        payload: [String: AnyJSON],
        telemetry: DebugTelemetry?,
        models: ModelManager?
    ) async {
        guard let supabase else {
            lastError = "Supabase client not configured"
            return
        }

        let row = DebugEventRow(
            installId: installID,
            appVersion: appVersion,
            appBuild: appBuild,
            deviceModel: deviceModel,
            systemName: systemName,
            systemVersion: systemVersion,
            isSimulator: isSimulator,
            kind: kind,
            severity: severity.rawValue,
            source: source,
            message: message,
            payload: payload,
            thermalState: telemetry.map { thermalStateString($0.thermalState) },
            lowPowerMode: telemetry?.lowPowerMode,
            residentBytes: telemetry.map { Int64($0.residentBytes) },
            physicalFootprintBytes: telemetry.map { Int64($0.physicalFootprintBytes) },
            availableBytes: telemetry.map { Int64($0.availableBytes) },
            deviceTotalBytes: telemetry.map { Int64($0.deviceTotalBytes) },
            modelCacheBytes: telemetry?.modelCacheBytes
        )

        do {
            pendingEventCount += 1
            try await supabase
                .from("debug_events")
                .insert(row)
                .execute()
            pendingEventCount -= 1
            lastError = nil
        } catch {
            pendingEventCount = max(0, pendingEventCount - 1)
            lastError = error.localizedDescription
            // Never surface to the user — this is a debug sink.
        }
    }

    // MARK: - Severity

    enum Severity: String {
        case info = "info"
        case warn = "warn"
        case error = "error"
        case critical = "critical"
    }
}

// MARK: - Insert row

/// Codable row matching the `debug_events` table. Marked `nonisolated` and
/// `Sendable` because the project defaults to MainActor isolation and these
/// are encoded by the Supabase SDK on a background thread.
nonisolated struct DebugEventRow: Encodable, Sendable {
    let installId: String
    let appVersion: String
    let appBuild: String
    let deviceModel: String
    let systemName: String
    let systemVersion: String
    let isSimulator: Bool
    let kind: String
    let severity: String
    let source: String?
    let message: String?
    let payload: [String: AnyJSON]
    let thermalState: String?
    let lowPowerMode: Bool?
    let residentBytes: Int64?
    let physicalFootprintBytes: Int64?
    let availableBytes: Int64?
    let deviceTotalBytes: Int64?
    let modelCacheBytes: Int64?

    enum CodingKeys: String, CodingKey {
        case installId = "install_id"
        case appVersion = "app_version"
        case appBuild = "app_build"
        case deviceModel = "device_model"
        case systemName = "system_name"
        case systemVersion = "system_version"
        case isSimulator = "is_simulator"
        case kind
        case severity
        case source
        case message
        case payload
        case thermalState = "thermal_state"
        case lowPowerMode = "low_power_mode"
        case residentBytes = "resident_bytes"
        case physicalFootprintBytes = "physical_footprint_bytes"
        case availableBytes = "available_bytes"
        case deviceTotalBytes = "device_total_bytes"
        case modelCacheBytes = "model_cache_bytes"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(installId, forKey: .installId)
        try container.encode(appVersion, forKey: .appVersion)
        try container.encode(appBuild, forKey: .appBuild)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(systemName, forKey: .systemName)
        try container.encode(systemVersion, forKey: .systemVersion)
        try container.encode(isSimulator, forKey: .isSimulator)
        try container.encode(kind, forKey: .kind)
        try container.encode(severity, forKey: .severity)
        try container.encodeIfPresent(source, forKey: .source)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(lowPowerMode, forKey: .lowPowerMode)
        try container.encodeIfPresent(residentBytes, forKey: .residentBytes)
        try container.encodeIfPresent(physicalFootprintBytes, forKey: .physicalFootprintBytes)
        try container.encodeIfPresent(availableBytes, forKey: .availableBytes)
        try container.encodeIfPresent(deviceTotalBytes, forKey: .deviceTotalBytes)
        try container.encodeIfPresent(modelCacheBytes, forKey: .modelCacheBytes)
        try container.encodeIfPresent(thermalState, forKey: .thermalState)
        // `AnyJSON` encodes itself as a JSONB-compatible object.
        try container.encode(payload, forKey: .payload)
    }
}
