import Foundation

/// The four on-device models powering Ask Palace.
nonisolated enum ModelRole: String, CaseIterable, Identifiable {
    case textEmbedding
    case visionUnderstanding
    case reranker
    case synthesis

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .textEmbedding: return "EmbeddingGemma 300M"
        case .visionUnderstanding: return "Qwen3-VL 2B"
        case .reranker: return "Qwen3 Reranker 0.6B"
        case .synthesis: return "Qwen3 1.7B"
        }
    }

    var purpose: String {
        switch self {
        case .textEmbedding: return "Turns every learning into a semantic vector for meaning-based search."
        case .visionUnderstanding: return "Reads attached photos and diagrams so images become searchable."
        case .reranker: return "Re-scores retrieved entries by true relevance to your question."
        case .synthesis: return "Writes the final answer from your own learnings, with citations."
        }
    }

    var symbol: String {
        switch self {
        case .textEmbedding: return "point.3.connected.trianglepath.dotted"
        case .visionUnderstanding: return "eye"
        case .reranker: return "arrow.up.arrow.down"
        case .synthesis: return "text.bubble"
        }
    }
}

nonisolated struct ModelSpec: Identifiable, Hashable {
    let role: ModelRole
    let hubId: String
    let approxBytes: Int64

    var id: String { hubId }

    /// Where the Hugging Face hub cache places this model's snapshot.
    var localDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(hubId, isDirectory: true)
    }

    var isDownloaded: Bool {
        let fm = FileManager.default
        let dir = localDirectory
        guard fm.fileExists(atPath: dir.appendingPathComponent("config.json").path) else {
            return false
        }
        let contents = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        return contents.contains { $0.hasSuffix(".safetensors") }
    }

    var bytesOnDisk: Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: localDirectory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    func deleteFromDisk() {
        try? FileManager.default.removeItem(at: localDirectory)
    }
}

nonisolated enum ModelCatalog {
    static let textEmbedding = ModelSpec(
        role: .textEmbedding,
        hubId: "mlx-community/embeddinggemma-300m-4bit",
        approxBytes: 250_000_000
    )
    static let vision = ModelSpec(
        role: .visionUnderstanding,
        hubId: "mlx-community/Qwen3-VL-Embedding-2B-4bit",
        approxBytes: 1_300_000_000
    )
    static let reranker = ModelSpec(
        role: .reranker,
        hubId: "mlx-community/Qwen3-Reranker-0.6B-4bit",
        approxBytes: 400_000_000
    )
    static let synthesis = ModelSpec(
        role: .synthesis,
        hubId: "mlx-community/Qwen3-1.7B-4bit",
        approxBytes: 1_000_000_000
    )

    static let all: [ModelSpec] = [textEmbedding, synthesis, reranker, vision]

    static func spec(for role: ModelRole) -> ModelSpec {
        switch role {
        case .textEmbedding: return textEmbedding
        case .visionUnderstanding: return vision
        case .reranker: return reranker
        case .synthesis: return synthesis
        }
    }
}
