import Accelerate
import Foundation

/// Small helpers for brute-force cosine similarity over stored vectors.
/// At personal-knowledge scale (hundreds to a few thousand entries) a vDSP
/// scan beats any index in simplicity and is instant.
nonisolated enum VectorMath {
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dot / denominator
    }

    /// Returns the ids of the `limit` most similar vectors, best first.
    static func topMatches(
        query: [Float],
        among vectors: [(id: String, vector: [Float])],
        limit: Int
    ) -> [(id: String, score: Float)] {
        vectors
            .map { (id: $0.id, score: cosineSimilarity(query, $0.vector)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
