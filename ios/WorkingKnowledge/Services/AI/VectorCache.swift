import Foundation

/// In-memory cache of the vectors `IndexingService` loads for brute-force
/// similarity scans. Every Ask Palace question used to re-read every
/// embedding row from SQLite; at a few thousand rows that's wasted disk I/O
/// on every keystroke of a conversation. This cache holds the decoded
/// `[Float]` arrays in memory and is invalidated on any write, so a stale
/// read is never possible — the tradeoff is a full reload after the next
/// index update rather than serving one row of stale data.
nonisolated final class VectorCache: @unchecked Sendable {
    static let shared = VectorCache()

    private let lock = NSLock()
    private var entryVectors: [(id: String, vector: [Float])]?
    private var imageVectors: [(id: String, entryId: String, vector: [Float])]?

    private init() {}

    func entryVectors(load: () -> [(id: String, vector: [Float])]) -> [(id: String, vector: [Float])] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = entryVectors { return cached }
        let loaded = load()
        entryVectors = loaded
        return loaded
    }

    func imageVectors(
        load: () -> [(id: String, entryId: String, vector: [Float])]
    ) -> [(id: String, entryId: String, vector: [Float])] {
        lock.lock()
        defer { lock.unlock() }
        if let cached = imageVectors { return cached }
        let loaded = load()
        imageVectors = loaded
        return loaded
    }

    /// Drops every cached list. Called after any embedding-table write.
    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        entryVectors = nil
        imageVectors = nil
    }
}
