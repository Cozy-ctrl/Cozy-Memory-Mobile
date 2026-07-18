import Foundation
import GRDB

// MARK: - Database records (plain rows; view models are assembled in PalaceStore)

nonisolated struct SubjectRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "subject"
    var id: String
    var name: String
    var symbolName: String
    var colorRaw: String
    var createdAt: Date
}

nonisolated struct TopicRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "topic"
    var id: String
    var subjectId: String
    var name: String
    var createdAt: Date
}

nonisolated struct EntryRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "entry"
    var id: String
    var topicId: String
    var question: String
    var learned: String
    var kindRaw: String
    var toolName: String
    var outcomeRaw: String
    var createdAt: Date

    /// The text that goes into the FTS index (topic/subject names appended by caller).
    var searchableText: String {
        "\(question) \(learned) \(toolName)"
    }
}

nonisolated struct AttachmentRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "attachment"
    var id: String
    var entryId: String
    var fileName: String
    var kindRaw: String
    var ocrText: String?
    var caption: String?
    var createdAt: Date
}

nonisolated struct EmbeddingRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "embedding"
    var id: String
    var entryId: String
    var ownerKind: String
    var ownerId: String
    var model: String
    var dim: Int
    var vector: Data
    var createdAt: Date

    var floats: [Float] {
        vector.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    static func encode(_ floats: [Float]) -> Data {
        floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

nonisolated struct AskExchangeRecord: Codable, Hashable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "askExchange"
    var id: String
    var question: String
    var answer: String
    var sourceIdsJSON: String
    var engine: String
    var createdAt: Date
}
