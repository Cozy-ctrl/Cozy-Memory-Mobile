import Foundation
import Darwin
import UIKit

/// Live device telemetry for the in-app debug top bar. Reads resident and
/// physical memory via Mach APIs, walks the model cache directory for disk
/// usage, and surfaces static system info (device, OS, chip, simulator flag).
@Observable
final class DebugTelemetry {
    // MARK: - Live memory
    private(set) var residentBytes: UInt64 = 0
    private(set) var physicalFootprintBytes: UInt64 = 0
    private(set) var availableBytes: UInt64 = 0
    private(set) var deviceTotalBytes: UInt64 = 0

    // MARK: - Disk (model cache)
    private(set) var modelCacheBytes: Int64 = 0

    // MARK: - Static system info
    let deviceModel: String
    let systemName: String
    let systemVersion: String
    let processorCount: Int
    let activeProcessorCount: Int
    let thermalState: ProcessInfo.ThermalState
    let isSimulator: Bool
    let lowPowerMode: Bool
    let processUptime: TimeInterval

    private var timer: Timer?

    init() {
        deviceModel = Self.machineName()
        systemName = UIDevice.current.systemName
        systemVersion = UIDevice.current.systemVersion
        processorCount = ProcessInfo.processInfo.processorCount
        activeProcessorCount = ProcessInfo.processInfo.activeProcessorCount
        thermalState = ProcessInfo.processInfo.thermalState
        isSimulator = AIAvailability.isOnDeviceSupported == false
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        processUptime = ProcessInfo.processInfo.systemUptime
        deviceTotalBytes = Self.physicalMemoryTotal()
        refresh()
    }

    deinit {
        timer?.invalidate()
    }

    /// Starts a 1-second refresh cadence. Safe to call multiple times.
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// One-shot snapshot. Called by the timer and on demand.
    func refresh() {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kerr = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            residentBytes = taskInfo.resident_size
        }

        // Physical footprint — the real memory cost iOS attributes to this
        // process. `task_vm_info` is the supported iOS path (the
        // vm_region_footprint_info API is macOS-only).
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let vkr = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        if vkr == KERN_SUCCESS {
            physicalFootprintBytes = vmInfo.phys_footprint
        } else {
            // Fallback: use resident if footprint is unavailable.
            physicalFootprintBytes = residentBytes
        }

        availableBytes = Self.availableMemory()
        modelCacheBytes = Self.modelCacheSize()
    }

    // MARK: - Helpers

    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    static func formatBytes(_ bytes: Int64) -> String {
        formatBytes(UInt64(max(0, bytes)))
    }

    private static func machineName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce("") { acc, elem in
            guard let value = elem.value as? Int8, value != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(value)))
        }
        return identifier.isEmpty ? "unknown" : identifier
    }

    private static func physicalMemoryTotal() -> UInt64 {
        // ProcessInfo.processInfo.physicalMemory returns host RAM in bytes.
        return ProcessInfo.processInfo.physicalMemory
    }

    /// Best-effort free/available memory estimate from host_statistics.
    private static func availableMemory() -> UInt64 {
        var vmStats = vm_statistics_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_VM_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let free = UInt64(vmStats.free_count) * pageSize
        // `inactive` + `speculative` pages are reclaimable under pressure.
        let reclaimable = (UInt64(vmStats.inactive_count) + UInt64(vmStats.speculative_count)) * pageSize
        return free + reclaimable
    }

    /// Walks the Hugging Face cache directory used by all four models.
    private static func modelCacheSize() -> Int64 {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let docs else { return 0 }
        let cache = docs
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
        let fm = FileManager.default
        guard
            let enumerator = fm.enumerator(
                at: cache,
                includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
            )
        else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }
}
