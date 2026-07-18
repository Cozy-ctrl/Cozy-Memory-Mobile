import Foundation

/// MLX models run on Apple silicon GPUs only — physical devices, never the
/// simulator. All UI gates on this so the cloud preview stays functional.
nonisolated enum AIAvailability {
    static var isOnDeviceSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    static let simulatorNotice =
        "On-device AI needs a real iPhone's chip. Everything else — capture, keyword search, attachments — works right here in the preview."
}

nonisolated enum AIError: LocalizedError {
    case simulatorUnsupported
    case modelNotLoaded
    case noModelsAvailable
    case cancelled

    var errorDescription: String? {
        switch self {
        case .simulatorUnsupported:
            return AIAvailability.simulatorNotice
        case .modelNotLoaded:
            return "The model isn't loaded yet. Download it in the Model Manager first."
        case .noModelsAvailable:
            return "No answer engine is available. Download the on-device models in the Model Manager."
        case .cancelled:
            return "Cancelled."
        }
    }
}

/// A tiny thread-safe flag used to stop token generation mid-stream.
nonisolated final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func cancel() {
        lock.lock()
        flag = true
        lock.unlock()
    }
}
