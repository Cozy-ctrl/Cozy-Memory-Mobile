import SwiftUI

/// Compact telemetry strip pinned to the top of the app for testing.
/// Shows live RAM (resident + footprint), free memory, model cache on disk,
/// CPU count, thermal state, low-power mode, device + OS, and per-model
/// load state. Tapping toggles a detailed expansion.
struct DebugTopBar: View {
    @Environment(ModelManager.self) private var models
    @State private var telemetry = DebugTelemetry()
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            compactRow
            if expanded {
                detailGrid
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Theme.surfaceHigh.opacity(0.96))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.cyan.opacity(0.35))
                .frame(height: 0.5)
        }
        .onAppear {
            telemetry.start()
        }
        .onDisappear {
            telemetry.stop()
        }
    }

    // MARK: - Compact

    private var compactRow: some View {
        HStack(spacing: 10) {
            chip(systemImage: "memorychip", text: "RAM \(DebugTelemetry.formatBytes(telemetry.residentBytes))")
            chip(systemImage: "arrow.down.to.bottom", text: "Free \(DebugTelemetry.formatBytes(telemetry.availableBytes))")
            chip(systemImage: "internaldrive", text: "Models \(DebugTelemetry.formatBytes(telemetry.modelCacheBytes))")
            Spacer(minLength: 0)
            thermalChip
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.cyan)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func chip(systemImage: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(Theme.ice)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Theme.surface, in: .capsule)
    }

    private var thermalChip: some View {
        let (label, color): (String, Color) = switch telemetry.thermalState {
        case .nominal: ("Cool", Theme.ok)
        case .fair: ("Fair", Theme.cyan)
        case .serious: ("Warm", Theme.warn)
        case .critical: ("Hot", Theme.hot)
        @unknown default: ("?", Theme.muted)
        }
        return HStack(spacing: 4) {
            Image(systemName: "thermometer.medium")
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 11, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.14), in: .capsule)
    }

    // MARK: - Expanded detail

    private var detailGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            systemRow
            Divider().overlay(Theme.border)
            memoryRow
            Divider().overlay(Theme.border)
            modelsRow
        }
        .padding(12)
    }

    private var systemRow: some View {
        HStack(alignment: .top, spacing: 16) {
            kvColumn([
                ("Device", telemetry.deviceModel),
                ("OS", "\(telemetry.systemName) \(telemetry.systemVersion)"),
                ("Simulator", telemetry.isSimulator ? "YES" : "no"),
            ])
            kvColumn([
                ("CPUs", "\(telemetry.activeProcessorCount)/\(telemetry.processorCount)"),
                ("Low Power", telemetry.lowPowerMode ? "ON" : "off"),
                ("Uptime", formatUptime(telemetry.processUptime)),
            ])
        }
    }

    private var memoryRow: some View {
        HStack(alignment: .top, spacing: 16) {
            kvColumn([
                ("Resident", DebugTelemetry.formatBytes(telemetry.residentBytes)),
                ("Footprint", DebugTelemetry.formatBytes(telemetry.physicalFootprintBytes)),
                ("Free", DebugTelemetry.formatBytes(telemetry.availableBytes)),
            ])
            kvColumn([
                ("Device RAM", DebugTelemetry.formatBytes(telemetry.deviceTotalBytes)),
                ("Models on disk", DebugTelemetry.formatBytes(telemetry.modelCacheBytes)),
                ("Used %", usedPercentString),
            ])
        }
    }

    private var modelsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Models")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.muted)
            HStack(spacing: 6) {
                ForEach(ModelCatalog.all) { spec in
                    modelPill(spec)
                }
            }
        }
    }

    private func modelPill(_ spec: ModelSpec) -> some View {
        let phase = models.phase(for: spec.role)
        let ready = phase == .ready
        let busy = phase.isBusy
        let color: Color = ready ? Theme.ok : (busy ? Theme.cyan : Theme.dim)
        return VStack(spacing: 2) {
            Image(systemName: spec.role.symbol)
                .font(.system(size: 12, weight: .semibold))
            Text(shortName(spec.role))
                .font(.system(size: 9, design: .monospaced))
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.12), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(color.opacity(0.4), lineWidth: 0.5)
        )
    }

    private func shortName(_ role: ModelRole) -> String {
        switch role {
        case .textEmbedding: return "Embed"
        case .imageEmbedding: return "Image"
        case .reranker: return "Rerank"
        case .synthesis: return "Qwen3"
        }
    }

    private var usedPercentString: String {
        guard telemetry.deviceTotalBytes > 0 else { return "—" }
        let used = Double(telemetry.physicalFootprintBytes) / Double(telemetry.deviceTotalBytes) * 100
        return String(format: "%.1f%%", used)
    }

    private func kvColumn(_ pairs: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(pairs.indices, id: \.self) { i in
                let pair = pairs[i]
                HStack(spacing: 6) {
                    Text(pair.0)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    Spacer(minLength: 0)
                    Text(pair.1)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.ice)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        if m < 60 { return "\(m)m" }
        return "\(m / 60)h \(m % 60)m"
    }
}
