import Foundation

/// Hybrid retrieval: FTS5 keyword matches and semantic vector matches are
/// fused with Reciprocal Rank Fusion, then optionally reranked by the
/// cross-encoder for true relevance.
final class RetrievalService {
    struct ScoredEntry: Identifiable {
        let entry: Entry
        var score: Double
        var id: String { entry.id }
    }

    private let store: PalaceStore
    private let embedding: EmbeddingService
    private let reranker: RerankerService
    private let indexing: IndexingService

    init(
        store: PalaceStore,
        embedding: EmbeddingService,
        reranker: RerankerService,
        indexing: IndexingService
    ) {
        self.store = store
        self.embedding = embedding
        self.reranker = reranker
        self.indexing = indexing
    }

    /// Keyword + semantic retrieval fused with RRF.
    func hybridCandidates(question: String, limit: Int = 12) async -> [ScoredEntry] {
        let keywordHits = store.keywordSearch(question, limit: 24).map { $0.id }

        var vectorHits: [String] = []
        if embedding.isReady {
            let vectors = indexing.loadEntryVectors()
            if !vectors.isEmpty,
               let query = try? await embedding.embedOne(question, asQuery: true),
               !query.isEmpty {
                vectorHits = VectorMath
                    .topMatches(query: query, among: vectors, limit: 24)
                    .filter { $0.score > 0.15 }
                    .map { $0.id }
            }
        }

        // Reciprocal Rank Fusion across both ranked lists.
        var fused: [String: Double] = [:]
        let k = 60.0
        for (rank, id) in keywordHits.enumerated() {
            fused[id, default: 0] += 1.0 / (k + Double(rank + 1))
        }
        for (rank, id) in vectorHits.enumerated() {
            fused[id, default: 0] += 1.0 / (k + Double(rank + 1))
        }

        let ranked = fused
            .sorted { $0.value > $1.value }
            .prefix(limit)
            .compactMap { pair -> ScoredEntry? in
                guard let entry = store.entry(id: pair.key) else { return nil }
                return ScoredEntry(entry: entry, score: pair.value)
            }
        return Array(ranked)
    }

    /// Cross-encoder rerank of the fused candidates (best-effort).
    func rerank(question: String, candidates: [ScoredEntry], keep: Int = 6) async -> [ScoredEntry] {
        guard reranker.isReady, candidates.count > 1 else {
            return Array(candidates.prefix(keep))
        }
        let inputs = candidates.map { scored in
            RerankerService.Candidate(
                id: scored.entry.id,
                text: "Q: \(scored.entry.question)\nA: \(scored.entry.learned)"
            )
        }
        do {
            let scores = try await reranker.scores(query: question, candidates: inputs)
            let reranked = candidates
                .map { ScoredEntry(entry: $0.entry, score: scores[$0.entry.id] ?? 0) }
                .sorted { $0.score > $1.score }
            return Array(reranked.prefix(keep))
        } catch {
            print("[RetrievalService] rerank failed, keeping fused order: \(error)")
            return Array(candidates.prefix(keep))
        }
    }
}
