import Foundation
import GRDB
import Observation

/// Keeps semantic vectors in sync with entries and attachments.
/// Text is embedded the moment an entry is saved (when the embedder is
/// loaded); attached photos get OCR immediately (still useful for keyword
/// search) and are embedded directly into the visual-semantic space once the
/// image embedder is loaded — no caption step in between.
@Observable
final class IndexingService {
    private unowned let store: PalaceStore
    private let database: AppDatabase
    private let embedding: EmbeddingService
    private let imageEmbedding: ImageEmbeddingService

    private(set) var isIndexing = false
    private(set) var lastError: String?

    init(
        store: PalaceStore,
        database: AppDatabase,
        embedding: EmbeddingService,
        imageEmbedding: ImageEmbeddingService
    ) {
        self.store = store
        self.database = database
        self.embedding = embedding
        self.imageEmbedding = imageEmbedding
    }

    /// Number of entries that have no *current-model* semantic vector yet.
    var unindexedCount: Int {
        let indexed = indexedEntryIds()
        return store.allEntries.filter { !indexed.contains($0.id) }.count
    }

    /// Vectors on disk whose `model` column doesn't match the model this
    /// build actually loads. Swapping EmbeddingGemma or Qwen3-VL-Embedding
    /// for a different checkpoint doesn't crash anything — the schema always
    /// recorded which model made each vector — but nothing checked it, so
    /// old vectors would just silently stop being returned by any query that
    /// filters on the current model id, and recall would quietly collapse.
    /// This is what lets `ModelManagerView` surface a "reindex needed"
    /// warning instead of that happening invisibly.
    var staleVectorCount: Int {
        (try? database.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM embedding
                    WHERE (ownerKind = 'entry' AND model != ?)
                       OR (ownerKind = 'attachmentImage' AND model != ?)
                    """,
                arguments: [ModelCatalog.textEmbedding.hubId, ModelCatalog.imageEmbedding.hubId]
            )
        }) ?? 0
    }

    private func indexedEntryIds() -> Set<String> {
        (try? database.dbQueue.read { db in
            try String.fetchSet(
                db,
                sql: "SELECT DISTINCT entryId FROM embedding WHERE ownerKind = 'entry' AND model = ?",
                arguments: [ModelCatalog.textEmbedding.hubId]
            )
        }) ?? []
    }

    /// Full refresh for one entry: attachment OCR + image embedding + text embedding.
    func indexEntry(id: String) async {
        guard let entry = store.entry(id: id) else { return }

        // 1. OCR every unread attachment (always available, cheap). This
        //    mutates the store, so re-fetch the entry afterwards.
        var analyzedAny = false
        for attachment in entry.attachments where attachment.ocrText == nil {
            let ocr = await OCRService.extractText(from: attachment.fileURL, kind: attachment.kind)
            if ocr != nil {
                store.updateAttachmentAnalysis(id: attachment.id, ocrText: ocr, caption: attachment.caption)
                analyzedAny = true
            }
        }

        let current = analyzedAny ? (store.entry(id: id) ?? entry) : entry

        // 2. Embed every image attachment directly (device + image embedder only).
        if imageEmbedding.isReady {
            for attachment in current.attachments where attachment.kind == .image {
                guard needsImageVector(attachmentId: attachment.id) else { continue }
                do {
                    let vector = try await imageEmbedding.embed(imageAt: attachment.fileURL)
                    guard !vector.isEmpty else { continue }
                    try storeVector(
                        vector,
                        entryId: current.id,
                        ownerKind: "attachmentImage",
                        ownerId: attachment.id,
                        model: ModelCatalog.imageEmbedding.hubId
                    )
                } catch {
                    lastError = error.localizedDescription
                    print("[IndexingService] image embed failed: \(error)")
                }
            }
        }

        // 3. Semantic vector for the entry text (device + text embedder only).
        guard embedding.isReady else { return }
        do {
            let vector = try await embedding.embedOne(current.embeddingText, asQuery: false)
            guard !vector.isEmpty else { return }
            try storeVector(
                vector,
                entryId: current.id,
                ownerKind: "entry",
                ownerId: current.id,
                model: ModelCatalog.textEmbedding.hubId
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[IndexingService] embed failed: \(error)")
        }
    }

    private func needsImageVector(attachmentId: String) -> Bool {
        let existingModel = try? database.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT model FROM embedding WHERE ownerKind = 'attachmentImage' AND ownerId = ?",
                arguments: [attachmentId]
            )
        }
        return existingModel.flatMap { $0 } != ModelCatalog.imageEmbedding.hubId
    }

    /// Embeds every entry that doesn't have a current-model vector yet (or
    /// all, if forced).
    func reindexAll(force: Bool = false) async {
        guard embedding.isReady || imageEmbedding.isReady else { return }
        isIndexing = true
        defer { isIndexing = false }

        if force {
            try? await database.dbQueue.write { db in
                try db.execute(sql: "DELETE FROM embedding WHERE ownerKind IN ('entry', 'attachmentImage')")
            }
            VectorCache.shared.invalidate()
        }
        await indexMissing()
    }

    func indexMissing() async {
        guard embedding.isReady || imageEmbedding.isReady else { return }
        isIndexing = true
        defer { isIndexing = false }

        let indexedText = indexedEntryIds()
        let indexedImages: Set<String> = (try? await database.dbQueue.read { db in
            try String.fetchSet(
                db,
                sql: "SELECT DISTINCT ownerId FROM embedding WHERE ownerKind = 'attachmentImage' AND model = ?",
                arguments: [ModelCatalog.imageEmbedding.hubId]
            )
        }) ?? []

        for entry in store.allEntries {
            let needsText = embedding.isReady && !indexedText.contains(entry.id)
            let needsImages = imageEmbedding.isReady
                && entry.attachments.contains { $0.kind == .image && !indexedImages.contains($0.id) }
            guard needsText || needsImages else { continue }
            await indexEntry(id: entry.id)
        }
    }

    /// Loads current-model entry text vectors for the brute-force scan.
    nonisolated func loadEntryVectors() -> [(id: String, vector: [Float])] {
        VectorCache.shared.entryVectors {
            let records = (try? AppDatabase.shared.dbQueue.read { db in
                try EmbeddingRecord
                    .filter(Column("ownerKind") == "entry")
                    .filter(Column("model") == ModelCatalog.textEmbedding.hubId)
                    .fetchAll(db)
            }) ?? []
            return records.map { (id: $0.entryId, vector: $0.floats) }
        }
    }

    /// Loads current-model attachment-image vectors for the brute-force scan.
    /// Returned tuples carry the owning entry id, since retrieval matches
    /// happen at entry granularity.
    nonisolated func loadImageVectors() -> [(id: String, entryId: String, vector: [Float])] {
        VectorCache.shared.imageVectors {
            let records = (try? AppDatabase.shared.dbQueue.read { db in
                try EmbeddingRecord
                    .filter(Column("ownerKind") == "attachmentImage")
                    .filter(Column("model") == ModelCatalog.imageEmbedding.hubId)
                    .fetchAll(db)
            }) ?? []
            return records.map { (id: $0.ownerId, entryId: $0.entryId, vector: $0.floats) }
        }
    }

    private func storeVector(
        _ vector: [Float], entryId: String, ownerKind: String, ownerId: String, model: String
    ) throws {
        let record = EmbeddingRecord(
            id: UUID().uuidString,
            entryId: entryId,
            ownerKind: ownerKind,
            ownerId: ownerId,
            model: model,
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
        VectorCache.shared.invalidate()
    }
}
