import Foundation
import Observation
import Helpers

/// Owns the model services, their download/load lifecycle, and the
/// background indexer. The Model Manager screen renders straight off this.
@Observable
final class ModelManager {
    enum Phase: Equatable {
        case notDownloaded
        case downloading(Double)
        case downloaded
        case loading
        case ready
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .downloading, .loading: return true
            default: return false
            }
        }
    }

    private(set) var phases: [ModelRole: Phase] = [:]
    private(set) var bytesOnDisk: [ModelRole: Int64] = [:]

    let embedding = EmbeddingService()
    let reranker = RerankerService()
    let synthesis = SynthesisService()
    private(set) var indexing: IndexingService?

    private let store: PalaceStore
    private let database: AppDatabase
    private var loadTasks: [ModelRole: Task<Void, Never>] = [:]
    private var reporter: DebugReporter?

    init(store: PalaceStore, database: AppDatabase = .shared) {
        self.store = store
        self.database = database
        let indexer = IndexingService(
            store: store,
            database: database,
            embedding: embedding
        )
        indexing = indexer
        refreshDiskState()

        store.onEntryNeedsIndexing = { [weak self] entryId in
            Task { @MainActor in
                await self?.indexing?.indexEntry(id: entryId)
            }
        }
    }

    /// Optional sink for model-load failures surfaced to the remote debug
    /// backend. Wired by the app entry point once the reporter exists.
    func attachReporter(_ reporter: DebugReporter) {
        self.reporter = reporter
    }

    var totalBytesOnDisk: Int64 {
        bytesOnDisk.values.reduce(0, +)
    }

    var isAnyBusy: Bool {
        phases.values.contains { $0.isBusy }
    }

    func phase(for role: ModelRole) -> Phase {
        phases[role] ?? .notDownloaded
    }

    /// True when the semantic pipeline can answer questions (embedder + LLM).
    var canAnswerLocally: Bool {
        synthesis.isReady
    }

    func refreshDiskState() {
        for spec in ModelCatalog.all {
            bytesOnDisk[spec.role] = spec.isDownloaded ? spec.bytesOnDisk : 0
            let current = phases[spec.role]
            if current == nil || current == .notDownloaded || current == .downloaded {
                phases[spec.role] = resolvedIdlePhase(for: spec)
            }
        }
    }

    private func resolvedIdlePhase(for spec: ModelSpec) -> Phase {
        if isLoaded(spec.role) { return .ready }
        return spec.isDownloaded ? .downloaded : .notDownloaded
    }

    private func isLoaded(_ role: ModelRole) -> Bool {
        switch role {
        case .embedding: return embedding.isReady
        case .reranker: return reranker.isReady
        case .synthesis: return synthesis.isReady
        }
    }

    /// Downloads (if needed) and loads a model into memory.
    func activate(_ role: ModelRole) {
        guard !phase(for: role).isBusy else { return }
        guard AIAvailability.isOnDeviceSupported else {
            phases[role] = .failed(AIAvailability.simulatorNotice)
            return
        }

        let spec = ModelCatalog.spec(for: role)
        phases[role] = spec.isDownloaded ? .loading : .downloading(0)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.load(role: role)
                self.phases[role] = .ready
                self.refreshDiskState()
                self.onModelBecameReady(role)
                self.reporter?.report(
                    kind: "model_load",
                    severity: .info,
                    source: "ModelManager",
                    message: "loaded \(role)",
                    payload: ["role": .string(String(describing: role))]
                )
            } catch {
                self.phases[role] = .failed(error.localizedDescription)
                self.refreshDiskState()
                self.reporter?.report(
                    kind: "model_load_failed",
                    severity: .error,
                    source: "ModelManager",
                    message: "failed to load \(role)",
                    payload: [
                        "role": .string(String(describing: role)),
                        "error": .string(error.localizedDescription),
                    ]
                )
            }
            self.loadTasks[role] = nil
        }
        loadTasks[role] = task
    }

    /// Ensures a role is loaded before use; throws if it can't be.
    func ensureLoaded(_ role: ModelRole) async throws {
        if isLoaded(role) { return }
        guard AIAvailability.isOnDeviceSupported else { throw AIError.simulatorUnsupported }
        guard ModelCatalog.spec(for: role).isDownloaded else { throw AIError.modelNotLoaded }
        if !phase(for: role).isBusy {
            activate(role)
        }
        // Wait for the in-flight activation.
        while phase(for: role).isBusy {
            try await Task.sleep(for: .milliseconds(150))
        }
        guard isLoaded(role) else { throw AIError.modelNotLoaded }
    }

    private func load(role: ModelRole) async throws {
        let handler: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                guard let self else { return }
                if case .downloading = self.phase(for: role) {
                    self.phases[role] = fraction >= 1.0 ? .loading : .downloading(fraction)
                }
            }
        }
        switch role {
        case .embedding: try await embedding.load(progressHandler: handler)
        case .reranker: try await reranker.load(progressHandler: handler)
        case .synthesis: try await synthesis.load(progressHandler: handler)
        }
    }

    private func onModelBecameReady(_ role: ModelRole) {
        if role == .embedding {
            Task { @MainActor in
                await indexing?.indexMissing()
            }
        }
    }

    func downloadAll() {
        for spec in ModelCatalog.all where !phase(for: spec.role).isBusy {
            if !isLoaded(spec.role) {
                activate(spec.role)
            }
        }
    }

    /// Auto-activates every role whose weights are already on disk.
    /// Called on app launch so previously-downloaded models are ready
    /// without a trip to Model Manager. Roles that aren't downloaded yet
    /// are left untouched. Loads are staggered so we never allocate all
    /// three concurrently on first appear.
    func autoloadDownloaded() {
        guard AIAvailability.isOnDeviceSupported else { return }
        let onDisk = ModelCatalog.all.filter { $0.isDownloaded && !isLoaded($0.role) }
        guard !onDisk.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Embedding first so indexing can start behind the others.
            let ordered = onDisk.sorted { lhs, rhs in
                (lhs.role == .embedding ? 0 : 1) < (rhs.role == .embedding ? 0 : 1)
            }
            for spec in ordered {
                guard !self.phase(for: spec.role).isBusy else { continue }
                self.activate(spec.role)
                // Wait for this role to settle before starting the next,
                // keeping peak memory bounded.
                while self.phase(for: spec.role).isBusy {
                    try? await Task.sleep(for: .milliseconds(200))
                    if Task.isCancelled { return }
                }
            }
        }
    }

    func delete(_ role: ModelRole) {
        loadTasks[role]?.cancel()
        loadTasks[role] = nil
        switch role {
        case .embedding: embedding.unload()
        case .reranker: reranker.unload()
        case .synthesis: synthesis.unload()
        }
        ModelCatalog.spec(for: role).deleteFromDisk()
        phases[role] = .notDownloaded
        refreshDiskState()
    }
}
