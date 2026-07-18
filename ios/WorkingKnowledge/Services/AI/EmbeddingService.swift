import Foundation
import MLX
import MLXEmbedders
import Observation
import Tokenizers

/// EmbeddingGemma-300m (4-bit, MLX) — turns text into semantic vectors.
/// Follows the model's prompt convention: queries and documents get
/// different task prefixes.
@Observable
final class EmbeddingService {
    private(set) var container: MLXEmbedders.ModelContainer?

    var isReady: Bool { container != nil }

    func load(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard container == nil else { return }
        guard AIAvailability.isOnDeviceSupported else { throw AIError.simulatorUnsupported }
        container = try await MLXEmbedders.loadModelContainer(
            configuration: MLXEmbedders.ModelConfiguration(id: ModelCatalog.textEmbedding.hubId)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    func unload() {
        container = nil
    }

    /// Embeds a batch of texts. `asQuery` picks the EmbeddingGemma prompt
    /// prefix for retrieval queries vs. indexed documents.
    func embed(texts: [String], asQuery: Bool) async throws -> [[Float]] {
        guard let container else { throw AIError.modelNotLoaded }
        guard !texts.isEmpty else { return [] }

        let prefixed = texts.map { text in
            asQuery
                ? "task: search result | query: \(text)"
                : "title: none | text: \(text)"
        }

        return await container.perform { model, tokenizer, pooling in
            let inputs = prefixed.map { text in
                Array(tokenizer.encode(text: text, addSpecialTokens: true).prefix(512))
            }
            let maxLength = inputs.reduce(into: 16) { acc, elem in
                acc = max(acc, elem.count)
            }
            let padId = tokenizer.eosTokenId ?? 0

            let padded = stacked(
                inputs.map { elem in
                    MLXArray(elem + Array(repeating: padId, count: maxLength - elem.count))
                }
            )
            let mask = (padded .!= padId)
            let tokenTypes = MLXArray.zeros(like: padded)
            let result = pooling(
                model(padded, positionIds: nil, tokenTypeIds: tokenTypes, attentionMask: mask),
                normalize: true,
                applyLayerNorm: true
            )
            result.eval()
            return result.map { $0.asArray(Float.self) }
        }
    }

    func embedOne(_ text: String, asQuery: Bool) async throws -> [Float] {
        try await embed(texts: [text], asQuery: asQuery).first ?? []
    }
}
