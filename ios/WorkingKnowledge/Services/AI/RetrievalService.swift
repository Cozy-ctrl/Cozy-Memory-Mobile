import Foundation

/// Hybrid retrieval: keyword (FTS5/BM25), text-semantic, image-semantic, and
/// a temporal list all get ranked independently, then fused with Reciprocal
/// Rank Fusion — never by comparing raw scores. That last part matters
/// because the text and image vectors live in two different, incomparable
/// spaces (an EmbeddingGemma text vector and a Qwen3-VL-Embedding image
/// vector aren't coordinates in the same universe), so RRF's "combine
/// rankings, not scores" is the only mathematically safe way to merge them.
final class RetrievalService {
    struct ScoredEntry: Identifiable {
        let entry: Entry
        var score: Double
        var id: String { entry.id }
    }

    /// Words that signal the question is asking about *when* something
    /// happened rather than *what*. When present, the most recent entries
    /// get injected into the fused ranking as their own list — this is the
    /// piece that lifts recall on time-anchored questions ("what did I do
    /// yesterday", "the whiteboard from last week") that keyword and
    /// semantic search alone tend to miss, since "recently" has no fixed
    /// semantic neighborhood.
    private static let temporalWords: Set<String> = [
        "today", "yesterday", "tonight", "morning", "afternoon", "evening",
        "recent", "recently", "lately", "latest", "newest", "last",
        "week", "weekend", "month", "yr", "year", "ago", "just", "now",
    ]

    private let store: PalaceStore
    private let embedding: EmbeddingService
    private let imageEmbedding: ImageEmbeddingService
    private let reranker: RerankerService
    private let indexing: IndexingService

    init(
        store: PalaceStore,
        embedding: EmbeddingService,
        imageEmbedding: ImageEmbeddingService,
        reranker: RerankerService,
        indexing: IndexingService
    ) {
        self.store = store
        self.embedding = embedding
        self.imageEmbedding = imageEmbedding
        self.reranker = reranker
        self.indexing = indexing
    }

    /// Keyword + text-semantic + image-semantic + temporal retrieval fused
    /// with RRF. `subjectId`, when set, scopes every one of the four lists
    /// to that subject before fusion (wing scoping) — the plumbing the UI
    /// doesn't expose yet, but `AskEngine.ask` already threads it through.
    func hybridCandidates(
        question: String, subjectId: String? = nil, limit: Int = 12
    ) async -> [ScoredEntry] {
        let scopedEntryIds: Set<String>? = subjectId.map { id in
            Set(store.allEntries.filter { $0.subjectId == id }.map { $0.id })
        }

        let keywordHits = store.keywordSearch(question, limit: 24)
            .map { $0.id }
            .filter { inScope($0, scopedEntryIds) }

        var textVectorHits: [String] = []
        if embedding.isReady {
            let vectors = indexing.loadEntryVectors()
                .filter { inScope($0.id, scopedEntryIds) }
            if !vectors.isEmpty,
               let query = try? await embedding.embedOne(question, asQuery: true),
               !query.isEmpty {
                textVectorHits = VectorMath
                    .topMatches(query: query, among: vectors, limit: 24)
                    .filter { $0.score > 0.15 }
                    .map { $0.id }
            }
        }

        var imageVectorHits: [String] = []
        if imageEmbedding.isReady {
            let imageVectors = indexing.loadImageVectors()
                .filter { inScope($0.entryId, scopedEntryIds) }
                .map { (id: $0.entryId, vector: $0.vector) }
            if !imageVectors.isEmpty,
               let queryText = try? await embedding.embedOne(question, asQuery: true),
               !queryText.isEmpty {
                // The text query and the image vectors live in different
                // spaces, so this "query" is only used to rank within the
                // image-semantic list itself — never compared against the
                // text list's scores. Ranks (not scores) are all RRF sees.
                imageVectorHits = VectorMath
                    .topMatches(query: queryText, among: imageVectors, limit: 24)
                    .filter { $0.score > 0.1 }
                    .map { $0.id }
            }
        }

        var temporalHits: [String] = []
        if isTemporalQuestion(question) {
            temporalHits = store.allEntries
                .filter { inScope($0.id, scopedEntryIds) }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(12)
                .map { $0.id }
        }

        // Reciprocal Rank Fusion across every ranked list that fired.
        var fused: [String: Double] = [:]
        let k = 60.0
        for list in [keywordHits, textVectorHits, imageVectorHits, temporalHits] {
            for (rank, id) in list.enumerated() {
                fused[id, default: 0] += 1.0 / (k + Double(rank + 1))
            }
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

    private func inScope(_ entryId: String, _ scope: Set<String>?) -> Bool {
        guard let scope else { return true }
        return scope.contains(entryId)
    }

    private func isTemporalQuestion(_ question: String) -> Bool {
        let tokens = question
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        return tokens.contains { Self.temporalWords.contains($0) }
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
