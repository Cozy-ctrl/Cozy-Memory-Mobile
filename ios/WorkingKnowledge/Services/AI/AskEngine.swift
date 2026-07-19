import Foundation
import FoundationModels
import Observation

/// Orchestrates one Ask Palace round: hybrid retrieval → rerank → grounded
/// answer synthesis (streaming). Prefers the local MLX pipeline; falls back
/// to Apple Intelligence (with the palace exposed as a tool) when the MLX
/// answer model isn't downloaded.
@Observable
final class AskEngine {
    enum Stage: Equatable {
        case idle
        case retrieving
        case reranking
        case generating
        case done
        case failed(String)
    }

    private(set) var stage: Stage = .idle
    private(set) var answer: String = ""
    private(set) var sources: [Entry] = []
    private(set) var engineLabel: String = ""
    private(set) var currentQuestion: String = ""

    private let store: PalaceStore
    private let models: ModelManager
    private let retrieval: RetrievalService
    private var cancellation = CancellationFlag()

    init(store: PalaceStore, models: ModelManager) {
        self.store = store
        self.models = models
        self.retrieval = RetrievalService(
            store: store,
            embedding: models.embedding,
            reranker: models.reranker,
            indexing: models.indexing ?? IndexingService(
                store: store,
                database: .shared,
                embedding: models.embedding
            )
        )
    }

    var isWorking: Bool {
        switch stage {
        case .retrieving, .reranking, .generating: return true
        default: return false
        }
    }

    func cancel() {
        cancellation.cancel()
    }

    func reset() {
        stage = .idle
        answer = ""
        sources = []
        engineLabel = ""
        currentQuestion = ""
    }

    /// - Parameter subjectId: When set, scopes retrieval (keyword, text,
    ///   image, and temporal) to a single subject before fusion. The UI
    ///   doesn't expose this yet, but the plumbing is complete end to end.
    func ask(_ rawQuestion: String, subjectId: String? = nil) async {
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isWorking else { return }

        cancellation = CancellationFlag()
        currentQuestion = question
        answer = ""
        sources = []
        engineLabel = ""
        stage = .retrieving

        // 1. Hybrid retrieval.
        let candidates = await retrieval.hybridCandidates(question: question, subjectId: subjectId)

        guard !candidates.isEmpty else {
            answer = "Nothing in your palace matches this yet. Capture what you find out, and next time the answer will be waiting here."
            stage = .done
            engineLabel = "No matches"
            store.recordAskExchange(
                question: question, answer: answer, sourceIds: [], engine: "none"
            )
            return
        }

        // 2. Rerank (best-effort; requires the reranker model).
        stage = .reranking
        if models.reranker.isReady || ModelCatalog.reranker.isDownloaded {
            try? await models.ensureLoaded(.reranker)
        }
        let top = await retrieval.rerank(question: question, candidates: candidates)
        sources = top.map { $0.entry }

        // 3. Answer synthesis.
        stage = .generating
        do {
            if AIAvailability.isOnDeviceSupported,
               models.synthesis.isReady || ModelCatalog.synthesis.isDownloaded {
                try await answerWithMLX(question: question)
            } else if let systemAnswer = try await answerWithAppleIntelligence(question: question) {
                answer = systemAnswer
                engineLabel = "Apple Intelligence"
            } else {
                throw AIError.noModelsAvailable
            }
            stage = .done
            store.recordAskExchange(
                question: question,
                answer: answer,
                sourceIds: sources.map { $0.id },
                engine: engineLabel
            )
        } catch {
            if answer.isEmpty {
                stage = .failed(error.localizedDescription)
            } else {
                // Keep partial output (e.g. user cancelled mid-stream).
                stage = .done
            }
        }
    }

    // MARK: - MLX pipeline

    private func answerWithMLX(question: String) async throws {
        try await models.ensureLoaded(.synthesis)
        engineLabel = "Qwen3 1.7B · on-device"

        let blocks = sources.enumerated().map { index, entry in
            """
            [\(index + 1)] (\(entry.subjectName) › \(entry.topicName), via \(entry.toolName))
            Q: \(entry.question)
            A: \(entry.learned)
            """
        }

        let flag = cancellation
        let final = try await models.synthesis.generateAnswer(
            question: question,
            contextBlocks: blocks,
            cancellation: flag
        ) { [weak self] text in
            Task { @MainActor in
                self?.answer = Self.cleanModelOutput(text)
            }
        }
        answer = Self.cleanModelOutput(final)
    }

    /// Strips any stray reasoning tags the model may emit.
    private static func cleanModelOutput(_ text: String) -> String {
        var output = text
        if let range = output.range(of: "</think>") {
            output = String(output[range.upperBound...])
        }
        output = output.replacingOccurrences(of: "<think>", with: "")
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Apple Intelligence fallback

    private func answerWithAppleIntelligence(question: String) async throws -> String? {
        guard #available(iOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }

        let session = LanguageModelSession(
            tools: [PalaceSearchTool()],
            instructions: """
                You answer questions strictly from the user's personal knowledge base. \
                Always call the searchPalace tool first, then answer concisely using only \
                what it returns. If nothing relevant comes back, say the palace has no \
                answer yet.
                """
        )
        let response = try await session.respond(to: question)
        return response.content
    }
}
