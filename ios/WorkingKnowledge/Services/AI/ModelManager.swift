import Foundation
import Observation

/// Owns the four model services, their download/load lifecycle, and the
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
    let vision = VisionCaptionService()
    private(set) var indexing: IndexingService?

    private let store: PalaceStore
    private let database: AppDatabase
    private var loadTasks: [ModelRole: Task<Void, Never>] = [:]

    init(store: PalaceStore, database: AppDatabase = .shared) {
        self.store = store
        self.database = database
        let indexer = IndexingService(
            store: store,
            database: database,
            embedding: embedding,
            vision: vision
        )
        indexing = indexer
        refreshDiskState()

        store.onEntryNeedsIndexing = { [weak self] entryId in
            Task { @MainActor in
                await self?.indexing?.indexEntry(id: entryId)
            }
        }
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
        embedding.isReady || synthesis.isReady
            ? synthesis.isReady
            : false
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
        case .textEmbedding: return embedding.isReady
        case .visionUnderstanding: return vision.isReady
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
            } catch {
                self.phases[role] = .failed(error.localizedDescription)
                self.refreshDiskState()
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
        case .textEmbedding: try await embedding.load(progressHandler: handler)
        case .visionUnderstanding: try await vision.load(progressHandler: handler)
        case .reranker: try await reranker.load(progressHandler: handler)
        case .synthesis: try await synthesis.load(progressHandler: handler)
        }
    }

    private func onModelBecameReady(_ role: ModelRole) {
        // New capability — refresh the semantic index in the background.
        if role == .textEmbedding || role == .visionUnderstanding {
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

    /// On launch (real device): quietly load whatever is already on disk,
    /// starting with the small embedder so capture-time indexing works.
    func loadDownloadedModels() {
        guard AIAvailability.isOnDeviceSupported else { return }
        for spec in [ModelCatalog.textEmbedding, ModelCatalog.reranker, ModelCatalog.synthesis]
        where spec.isDownloaded && !isLoaded(spec.role) {
            activate(spec.role)
        }
    }

    func delete(_ role: ModelRole) {
        loadTasks[role]?.cancel()
        loadTasks[role] = nil
        switch role {
        case .textEmbedding: embedding.unload()
        case .visionUnderstanding: vision.unload()
        case .reranker: reranker.unload()
        case .synthesis: synthesis.unload()
        }
        ModelCatalog.spec(for: role).deleteFromDisk()
        phases[role] = .notDownloaded
        refreshDiskState()
    }
}
