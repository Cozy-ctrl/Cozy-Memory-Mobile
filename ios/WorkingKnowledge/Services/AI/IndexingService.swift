import Foundation
import GRDB
import Observation

/// Keeps semantic vectors in sync with entries and attachments. Both entry
/// text and attached images are embedded by the same Qwen3-VL-Embedding
/// model, so they share one vector space — text queries can hit photo
/// vectors directly, with no captioning step and no RRF between modalities.
@Observable
final class IndexingService {
    private unowned let store: PalaceStore
    private let database: AppDatabase
    private let embedding: EmbeddingService

    private(set) var isIndexing = false
    private(set) var lastError: String?

    init(
        store: PalaceStore,
        database: AppDatabase,
        embedding: EmbeddingService
    ) {
        self.store = store
        self.database = database
        self.embedding = embedding
    }

    /// Number of entries that have no *current-model* semantic vector yet.
    var unindexedCount: Int {
        let indexed = indexedEntryIds()
        return store.allEntries.filter { !indexed.contains($0.id) }.count
    }

    /// Vectors on disk whose `model` column doesn't match the model this
    /// build actually loads. Swapping Qwen3-VL-Embedding for a different
    /// checkpoint doesn't crash anything — the schema always recorded which
    /// model made each vector — but nothing checked it, so old vectors
    /// would just silently stop being returned by any query that filters on
    /// the current model id, and recall would quietly collapse. This is
    /// what lets `ModelManagerView` surface a "reindex needed" warning
    /// instead of that happening invisibly.
    var staleVectorCount: Int {
        (try? database.dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM embedding
                    WHERE model != ?
                    """,
                arguments: [ModelCatalog.embedding.hubId]
            )
        }) ?? 0
    }

    private func indexedEntryIds() -> Set<String> {
        (try? database.dbQueue.read { db in
            try String.fetchSet(
                db,
                sql: "SELECT DISTINCT entryId FROM embedding WHERE ownerKind = 'entry' AND model = ?",
                arguments: [ModelCatalog.embedding.hubId]
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

        guard embedding.isReady else { return }

        // 2. Embed every image attachment into the shared space.
        for attachment in current.attachments where attachment.kind == .image {
            guard needsVector(ownerKind: "attachmentImage", ownerId: attachment.id) else { continue }
            do {
                let vector = try await embedding.embed(imageAt: attachment.fileURL)
                guard !vector.isEmpty else { continue }
                try storeVector(
                    vector,
                    entryId: current.id,
                    ownerKind: "attachmentImage",
                    ownerId: attachment.id,
                    model: ModelCatalog.embedding.hubId
                )
            } catch {
                lastError = error.localizedDescription
                print("[IndexingService] image embed failed: \(error)")
            }
        }

        // 3. Semantic vector for the entry text.
        do {
            let vector = try await embedding.embedOne(current.embeddingText, asQuery: false)
            guard !vector.isEmpty else { return }
            try storeVector(
                vector,
                entryId: current.id,
                ownerKind: "entry",
                ownerId: current.id,
                model: ModelCatalog.embedding.hubId
            )
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            print("[IndexingService] embed failed: \(error)")
        }
    }

    private func needsVector(ownerKind: String, ownerId: String) -> Bool {
        let existingModel = try? database.dbQueue.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT model FROM embedding WHERE ownerKind = ? AND ownerId = ?",
                arguments: [ownerKind, ownerId]
            )
        }
        return existingModel.flatMap { $0 } != ModelCatalog.embedding.hubId
    }

    /// Embeds every entry that doesn't have a current-model vector yet (or
    /// all, if forced).
    func reindexAll(force: Bool = false) async {
        guard embedding.isReady else { return }
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
        guard embedding.isReady else { return }
        isIndexing = true
        defer { isIndexing = false }

        let indexedText = indexedEntryIds()
        let indexedImages: Set<String> = (try? await database.dbQueue.read { db in
            try String.fetchSet(
                db,
                sql: "SELECT DISTINCT ownerId FROM embedding WHERE ownerKind = 'attachmentImage' AND model = ?",
                arguments: [ModelCatalog.embedding.hubId]
            )
        }) ?? []

        for entry in store.allEntries {
            let needsText = !indexedText.contains(entry.id)
            let needsImages = entry.attachments.contains { $0.kind == .image && !indexedImages.contains($0.id) }
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
                    .filter(Column("model") == ModelCatalog.embedding.hubId)
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
                    .filter(Column("model") == ModelCatalog.embedding.hubId)
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
