import Accelerate
import Foundation

/// Small helpers for brute-force similarity over stored vectors.
/// At personal-knowledge scale (hundreds to a few thousand entries) a vDSP
/// scan beats any index in simplicity and is instant.
///
/// Every vector this app stores is normalized to unit length at write time
/// (`normalized(_:)`, applied by both `EmbeddingService` and
/// `ImageEmbeddingService`). For unit vectors, cosine similarity and dot
/// product are the same number — dot product just skips recomputing both
/// norms on every comparison, which matters when the same query gets
/// scanned against every stored vector.
nonisolated enum VectorMath {
    static func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return dot
    }

    /// Cosine similarity, kept for vectors that aren't guaranteed unit-length.
    static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var normA: Float = 0
        var normB: Float = 0
        vDSP_svesq(a, 1, &normA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &normB, vDSP_Length(b.count))
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        return dotProduct(a, b) / denominator
    }

    /// L2-normalizes a vector to unit length so downstream comparisons can
    /// use plain dot product.
    static func normalized(_ vector: [Float]) -> [Float] {
        guard !vector.isEmpty else { return vector }
        var sumSquares: Float = 0
        vDSP_svesq(vector, 1, &sumSquares, vDSP_Length(vector.count))
        let norm = sqrt(sumSquares)
        guard norm > 0 else { return vector }
        var scaled = [Float](repeating: 0, count: vector.count)
        var divisor = norm
        vDSP_vsdiv(vector, 1, &divisor, &scaled, 1, vDSP_Length(vector.count))
        return scaled
    }

    /// Returns the ids of the `limit` most similar vectors, best first.
    /// Assumes both `query` and every stored vector are unit-normalized.
    static func topMatches(
        query: [Float],
        among vectors: [(id: String, vector: [Float])],
        limit: Int
    ) -> [(id: String, score: Float)] {
        vectors
            .map { (id: $0.id, score: dotProduct(query, $0.vector)) }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
    }
}
