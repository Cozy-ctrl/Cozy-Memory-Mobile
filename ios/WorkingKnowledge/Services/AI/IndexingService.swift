import Foundation
import GRDB
import Observation

/// Keeps semantic vectors in sync with entries and attachments.
/// Text is embedded the moment an entry is saved (when the embedder is
/// loaded); attachments get OCR immediately and a vision caption when the
/// VLM is available.
@Observable
final class IndexingService {
    private unowned let store: PalaceStore
    private let database: AppDatabase
    private let embedding: EmbeddingService
    private let vision: VisionCaptionService

    private(set) var isIndexing = false
    private(set) var lastError: String?

    init(
        store: PalaceStore,
        database: AppDatabase,
        embedding: EmbeddingService,
        vision: VisionCaptionService
    ) {
        self.store = store
        self.database = database
        self.embedding = embedding
        self.vision = vision
    }

    /// Number of entries that have no semantic vector yet.
    var unindexedCount: Int {
        let indexed = (try? database.dbQueue.read { db in
            try String.fetchSet(
                db, sql: "SELECT DISTINCT entryId FROM embedding WHERE ownerKind = 'entry'"
            )
        }) ?? []
        return store.allEntries.filter { !indexed.contains($0.id) }.count
    }

    /// Full refresh for one entry: attachment analysis + text embedding.
    func indexEntry(id: String) async {
        guard let entry = store.entry(id: id) else { return }

        // 1. Analyze attachments that haven't been read yet (OCR always works;
        //    vision caption only when the VLM is loaded). This mutates the store,
        //    so re-fetch the entry afterwards.
        var analyzedAny = false
        for attachment in entry.attachments where attachment.ocrText == nil && attachment.caption == nil {
            let ocr = await OCRService.extractText(from: attachment.fileURL, kind: attachment.kind)
            var caption: String?
            if attachment.kind == .image, vision.isReady {
                caption = try? await vision.describeImage(at: attachment.fileURL)
            }
            if ocr != nil || caption != nil {
                store.updateAttachmentAnalysis(id: attachment.id, ocrText: ocr, caption: caption)
                analyzedAny = true
            }
        }

        let current = analyzedAny ? (store.entry(id: id) ?? entry) : entry

        // 2. Semantic vector for the entry text (device + embedder only).
        guard embedding.isReady else { return }
        do {
            let vector = try await embedding.embedOne(current.embeddingText, asQuery: false)
            guard !vector.isEmpty else { return }
            try storeVector(vector, entryId: current.id, ownerKind: "entry", ownerId: current.id)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[IndexingService] embed failed: \(error)")
        }
    }

    /// Embeds every entry that doesn't have a vector yet (or all, if forced).
    func reindexAll(force: Bool = false) async {
        guard embedding.isReady else { return }
        isIndexing = true
        defer { isIndexing = false }

        if force {
            try? await database.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM embedding WHERE ownerKind = 'entry'")
            }
        }
        await indexMissing()
    }

    func indexMissing() async {
        guard embedding.isReady else { return }
        isIndexing = true
        defer { isIndexing = false }

        let indexed = (try? await database.dbQueue.read { db in
            try String.fetchSet(
                db, sql: "SELECT DISTINCT entryId FROM embedding WHERE ownerKind = 'entry'"
            )
        }) ?? []

        for entry in store.allEntries where !indexed.contains(entry.id) {
            await indexEntry(id: entry.id)
        }
    }

    /// Loads all stored entry vectors for the brute-force similarity scan.
    nonisolated func loadEntryVectors() -> [(id: String, vector: [Float])] {
        let records = (try? AppDatabase.shared.dbQueue.read { db in
            try EmbeddingRecord
                .filter(Column("ownerKind") == "entry")
                .fetchAll(db)
        }) ?? []
        return records.map { (id: $0.entryId, vector: $0.floats) }
    }

    private func storeVector(
        _ vector: [Float], entryId: String, ownerKind: String, ownerId: String
    ) throws {
        let record = EmbeddingRecord(
            id: UUID().uuidString,
            entryId: entryId,
            ownerKind: ownerKind,
            ownerId: ownerId,
            model: ModelCatalog.textEmbedding.hubId,
            dim: vector.count,
            vector: EmbeddingRecord.encode(vector),
            createdAt: Date()
        )
        try database.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM embedding WHERE ownerKind = ? AND ownerId = ?",
                arguments: [ownerKind, ownerId]
            )
            try record.insert(db)
        }
    }
}
