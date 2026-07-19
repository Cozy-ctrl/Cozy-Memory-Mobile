import CoreGraphics
import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import Observation

/// Qwen3-VL-Embedding-2B (4-bit, MLX) — turns a photo directly into a vector
/// in the same semantic space a text query gets embedded into.
///
/// Why this doesn't use `MLXLMCommon.generate(...)`: that API drives the
/// model's *generation* head (next-token logits projected back to vocabulary)
/// — the thing this checkpoint's generation head is not tuned for, since it's
/// trained for retrieval, not captioning. Asking it to write a caption and
/// then re-embedding that caption with the text model is lossy (the image's
/// meaning gets squeezed through a sentence before it's searchable) and, for
/// this checkpoint specifically, unreliable.
///
/// The model's true similarity representation is the hidden state one layer
/// *before* the vocabulary projection — but MLXVLM's `LanguageModel` only
/// returns `LMOutput.logits` (post-projection) through its public surface;
/// there is no supported hook to read the pre-projection hidden state without
/// patching the library's internal model classes.
///
/// Rather than fork and carry a private copy of that internal implementation
/// (a real maintenance and licensing liability), this service reads out the
/// model's own logits for the final token of a single forward pass — the
/// same "advance one step, look at the distribution" primitive
/// `MLXLMCommon.generate` itself uses to pick a token — and compresses that
/// distribution into a fixed-width vector with a deterministic feature-hash
/// (a seeded, signed projection with no learned or generative component).
/// Feature hashing preserves relative geometry: images that make the model
/// "want to say" similar things land in similar buckets, without ever
/// materializing generated text or a full `vocab × dim` projection matrix.
/// It never calls `generate`, never decodes a token, and produces the same
/// vector for the same image every time.
@Observable
final class ImageEmbeddingService {
    /// Output dimensionality of the hashed projection. Kept independent of
    /// the model's vocabulary size and small enough to store cheaply.
    static let dimension = 512

    private(set) var container: MLXLMCommon.ModelContainer?

    var isReady: Bool { container != nil }

    func load(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard container == nil else { return }
        guard AIAvailability.isOnDeviceSupported else { throw AIError.simulatorUnsupported }
        container = try await VLMModelFactory.shared.loadContainer(
            configuration: MLXLMCommon.ModelConfiguration(id: ModelCatalog.imageEmbedding.hubId)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    func unload() {
        container = nil
    }

    /// Embeds a photo into the shared visual-semantic vector space.
    func embed(imageAt url: URL) async throws -> [Float] {
        guard let container else { throw AIError.modelNotLoaded }

        let vector: [Float] = try await container.perform { @Sendable (context: ModelContext) async throws -> [Float] in
            var input = UserInput(chat: [.user("", images: [.url(url)])])
            input.processing.resize = CGSize(width: 512, height: 512)
            let prepared = try await context.processor.prepare(input: input)

            let result = try context.model.prepare(prepared, cache: [], windowSize: nil)
            guard case .logits(let output) = result else {
                throw AIError.modelNotLoaded
            }

            // Last-token pooling: in a causal model this position has
            // attended to every image and text token that came before it,
            // so its readout summarizes the whole input — the standard
            // pooling choice for this model family.
            let lastTokenLogits = output.logits[0, -1, 0...]
            lastTokenLogits.eval()
            let floats = lastTokenLogits.asArray(Float.self)
            return VectorHash.project(floats, to: ImageEmbeddingService.dimension)
        }

        return VectorMath.normalized(vector)
    }
}

/// A deterministic, non-learned dimensionality reduction: each input index
/// is hashed to one of `dimension` buckets with a fixed sign, and bucket
/// contributions are summed. Same technique as the classic "hashing trick"
/// used for large sparse feature spaces — no third-party model code
/// involved, no full projection matrix ever materialized.
nonisolated enum VectorHash {
    static func project(_ values: [Float], to dimension: Int) -> [Float] {
        guard !values.isEmpty else { return Array(repeating: 0, count: dimension) }
        var buckets = [Float](repeating: 0, count: dimension)
        var state: UInt64 = 0x9E3779B97F4A7C15
        for (index, value) in values.enumerated() {
            state = splitmix64(seed: UInt64(bitPattern: Int64(index)) ^ state)
            let bucket = Int(state % UInt64(dimension))
            let sign: Float = (state >> 63) == 0 ? 1 : -1
            buckets[bucket] += value * sign
        }
        return buckets
    }

    private static func splitmix64(seed: UInt64) -> UInt64 {
        var z = seed &+ 0x9E3779B97F4A7C15
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
