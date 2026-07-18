import CoreGraphics
import Foundation
import MLXLMCommon
import MLXVLM
import Observation

/// Qwen3-VL-Embedding-2B (4-bit, MLX) — the vision model that reads attached
/// photos and diagrams. Its description (plus on-device OCR) is what makes
/// images semantically searchable.
@Observable
final class VisionCaptionService {
    private(set) var container: MLXLMCommon.ModelContainer?

    var isReady: Bool { container != nil }

    func load(progressHandler: @escaping @Sendable (Double) -> Void) async throws {
        guard container == nil else { return }
        guard AIAvailability.isOnDeviceSupported else { throw AIError.simulatorUnsupported }
        container = try await VLMModelFactory.shared.loadContainer(
            configuration: MLXLMCommon.ModelConfiguration(id: ModelCatalog.vision.hubId)
        ) { progress in
            progressHandler(progress.fractionCompleted)
        }
    }

    func unload() {
        container = nil
    }

    /// Produces a compact description of the image for indexing.
    func describeImage(at url: URL) async throws -> String {
        guard let container else { throw AIError.modelNotLoaded }

        return try await container.perform { context in
            var input = UserInput(
                chat: [
                    .user(
                        "Describe this image in two sentences for a search index, then list any visible text, part numbers, wire colors, or labels.",
                        images: [.url(url)]
                    )
                ]
            )
            input.processing.resize = CGSize(width: 512, height: 512)
            let prepared = try await context.processor.prepare(input: input)
            let result = try MLXLMCommon.generate(
                input: prepared,
                parameters: GenerateParameters(temperature: 0.3),
                context: context
            ) { tokens in
                tokens.count >= 240 ? .stop : .more
            }
            return result.output
        }
    }
}
