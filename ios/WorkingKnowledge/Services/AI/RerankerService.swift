import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Observation
import Tokenizers

/// Qwen3-Reranker-0.6B (4-bit, MLX) — scores query/document pairs by reading
/// the model's yes/no logits with the official reranker prompt format.
@Observable
final class RerankerService {
    private(set) var container: MLXLMCommon.ModelContainer?

    var isReady: Bool { container != nil }

    func load(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard container == nil else { return }
        guard AIAvailability.isOnDeviceSupported else { throw AIError.simulatorUnsupported }
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: MLXLMCommon.ModelConfiguration(id: ModelCatalog.reranker.hubId)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    func unload() {
        container = nil
    }

    struct Candidate: Sendable {
        let id: String
        let text: String
    }

    /// Returns P("yes") per candidate id — the probability that the document
    /// answers the query.
    func scores(query: String, candidates: [Candidate]) async throws -> [String: Double] {
        guard let container else { throw AIError.modelNotLoaded }
        guard !candidates.isEmpty else { return [:] }

        let instruction =
            "Given a personal knowledge base of saved learnings, retrieve entries that answer the user's question"

        return try await container.perform { context in
            var results: [String: Double] = [:]
            let yesId = context.tokenizer.encode(text: "yes", addSpecialTokens: false).first ?? 0
            let noId = context.tokenizer.encode(text: "no", addSpecialTokens: false).first ?? 0

            for candidate in candidates {
                let document = String(candidate.text.prefix(1200))
                let prompt = """
                    <|im_start|>system
                    Judge whether the Document meets the requirements based on the Query and the Instruct provided. Note that the answer can only be "yes" or "no".<|im_end|>
                    <|im_start|>user
                    <Instruct>: \(instruction)
                    <Query>: \(query)
                    <Document>: \(document)<|im_end|>
                    <|im_start|>assistant
                    <think>

                    </think>

                    """
                let tokens = context.tokenizer.encode(text: prompt)
                let logits = context.model(MLXArray(tokens)[.newAxis], cache: nil)
                let last = logits[0..., -1, 0...]
                last.eval()
                let yesLogit = Double(last[0, yesId].item(Float.self))
                let noLogit = Double(last[0, noId].item(Float.self))
                let peak = max(yesLogit, noLogit)
                let yesExp = exp(yesLogit - peak)
                let noExp = exp(noLogit - peak)
                results[candidate.id] = yesExp / (yesExp + noExp)
            }
            return results
        }
    }
}
