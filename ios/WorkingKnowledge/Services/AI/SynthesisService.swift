import Foundation
import MLXLLM
import MLXLMCommon
import Observation
import Tokenizers

/// Qwen3-1.7B (4-bit, MLX) — writes the final grounded answer from the
/// retrieved learnings, streaming tokens as they decode.
@Observable
final class SynthesisService {
    private(set) var container: MLXLMCommon.ModelContainer?

    var isReady: Bool { container != nil }

    func load(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard container == nil else { return }
        guard AIAvailability.isOnDeviceSupported else { throw AIError.simulatorUnsupported }
        container = try await LLMModelFactory.shared.loadContainer(
            configuration: MLXLMCommon.ModelConfiguration(id: ModelCatalog.synthesis.hubId)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    func unload() {
        container = nil
    }

    /// Generates an answer grounded in the numbered context blocks.
    /// `onUpdate` receives the full decoded text so far (not a delta).
    func generateAnswer(
        question: String,
        contextBlocks: [String],
        cancellation: CancellationFlag,
        onUpdate: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let container else { throw AIError.modelNotLoaded }

        let systemPrompt = """
            You are Palace, the voice of the user's personal knowledge base. \
            Answer the question using ONLY the numbered learnings provided. \
            Be concise and practical. Cite the learnings you used inline like [1] or [2]. \
            If the learnings don't contain the answer, say so plainly and suggest what to capture next. \
            Never invent facts that aren't in the learnings.
            """

        let contextText = contextBlocks.isEmpty
            ? "(no saved learnings matched)"
            : contextBlocks.joined(separator: "\n\n")

        let userPrompt = """
            My saved learnings:

            \(contextText)

            My question: \(question)
            """

        return try await container.perform { context in
            let input = try await context.processor.prepare(
                input: UserInput(
                    chat: [.system(systemPrompt), .user(userPrompt)],
                    additionalContext: ["enable_thinking": false]
                )
            )
            let parameters = GenerateParameters(temperature: 0.4, topP: 0.95)
            let result = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            ) { tokens in
                if cancellation.isCancelled {
                    return .stop
                }
                if tokens.count % 3 == 0 || tokens.count < 3 {
                    onUpdate(context.tokenizer.decode(tokens: tokens))
                }
                return tokens.count >= 700 ? .stop : .more
            }
            return result.output
        }
    }
}
