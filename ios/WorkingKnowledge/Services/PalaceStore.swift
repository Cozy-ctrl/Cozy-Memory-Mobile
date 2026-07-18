import Foundation
import GRDB
import Observation

/// One question/answer round from the Ask tab, persisted as history.
nonisolated struct AskExchange: Identifiable, Hashable {
    let id: String
    var question: String
    var answer: String
    var sourceIds: [String]
    var engine: String
    var createdAt: Date
}

/// Single source of truth for the palace. Wraps the GRDB database, exposes
/// value snapshots to SwiftUI, and keeps the FTS5 index in sync with writes.
@Observable
final class PalaceStore {
    private let database: AppDatabase

    private(set) var subjects: [Subject] = []
    private(set) var askHistory: [AskExchange] = []

    /// Set by the AI stack: called whenever an entry's content changes so its
    /// semantic vector can be refreshed in the background.
    @ObservationIgnored var onEntryNeedsIndexing: (@Sendable (String) -> Void)?

    init(database: AppDatabase = .shared) {
        self.database = database
        SeedData.seedIfNeeded(database: database)
        reload()
    }

    var allEntries: [Entry] {
        subjects.flatMap { $0.allEntries }.sorted { $0.createdAt > $1.createdAt }
    }

    var toolCount: Int {
        Set(allEntries.map { $0.toolName }).count
    }

    // MARK: - Lookup

    func subject(id: String) -> Subject? {
        subjects.first { $0.id == id }
    }

    func entry(id: String) -> Entry? {
        for subject in subjects {
            for topic in subject.topics {
                if let match = topic.entries.first(where: { $0.id == id }) {
                    return match
                }
            }
        }
        return nil
    }

    func entries(ids: [String]) -> [Entry] {
        ids.compactMap { entry(id: $0) }
    }

    // MARK: - Snapshot

    func reload() {
        do {
            let (subjectRecords, topicRecords, entryRecords, attachmentRecords, askRecords) =
                try database.dbQueue.read { db in
                    (
                        try SubjectRecord.order(Column("createdAt")).fetchAll(db),
                        try TopicRecord.order(Column("createdAt")).fetchAll(db),
                        try EntryRecord.order(Column("createdAt").desc).fetchAll(db),
                        try AttachmentRecord.order(Column("createdAt")).fetchAll(db),
                        try AskExchangeRecord.order(Column("createdAt").desc).fetchAll(db)
                    )
                }

            let attachmentsByEntry = Dictionary(grouping: attachmentRecords) { $0.entryId }
            let subjectById = Dictionary(uniqueKeysWithValues: subjectRecords.map { ($0.id, $0) })

            var entriesByTopic: [String: [Entry]] = [:]
            let topicById = Dictionary(uniqueKeysWithValues: topicRecords.map { ($0.id, $0) })
            for record in entryRecords {
                guard let topic = topicById[record.topicId],
                      let subject = subjectById[topic.subjectId] else { continue }
                let attachments = (attachmentsByEntry[record.id] ?? []).map { att in
                    Attachment(
                        id: att.id,
                        entryId: att.entryId,
                        fileName: att.fileName,
                        kindRaw: att.kindRaw,
                        ocrText: att.ocrText,
                        caption: att.caption,
                        createdAt: att.createdAt
                    )
                }
                let entry = Entry(
                    id: record.id,
                    topicId: record.topicId,
                    question: record.question,
                    learned: record.learned,
                    kindRaw: record.kindRaw,
                    toolName: record.toolName,
                    outcomeRaw: record.outcomeRaw,
                    createdAt: record.createdAt,
                    topicName: topic.name,
                    subjectId: subject.id,
                    subjectName: subject.name,
                    subjectSymbol: subject.symbolName,
                    subjectColorRaw: subject.colorRaw,
                    attachments: attachments
                )
                entriesByTopic[record.topicId, default: []].append(entry)
            }

            var topicsBySubject: [String: [Topic]] = [:]
            for record in topicRecords {
                let topic = Topic(
                    id: record.id,
                    subjectId: record.subjectId,
                    name: record.name,
                    createdAt: record.createdAt,
                    entries: entriesByTopic[record.id] ?? []
                )
                topicsBySubject[record.subjectId, default: []].append(topic)
            }

            subjects = subjectRecords.map { record in
                Subject(
                    id: record.id,
                    name: record.name,
                    symbolName: record.symbolName,
                    colorRaw: record.colorRaw,
                    createdAt: record.createdAt,
                    topics: topicsBySubject[record.id] ?? []
                )
            }

            askHistory = askRecords.map { record in
                let ids = (try? JSONDecoder().decode(
                    [String].self, from: Data(record.sourceIdsJSON.utf8)
                )) ?? []
                return AskExchange(
                    id: record.id,
                    question: record.question,
                    answer: record.answer,
                    sourceIds: ids,
                    engine: record.engine,
                    createdAt: record.createdAt
                )
            }

            writeCatalog()
        } catch {
            print("[PalaceStore] reload failed: \(error)")
        }
    }

    // MARK: - Subjects & topics

    @discardableResult
    func addSubject(name: String, symbolName: String, colorRaw: String) -> Subject? {
        let record = SubjectRecord(
            id: UUID().uuidString,
            name: name,
            symbolName: symbolName,
            colorRaw: colorRaw,
            createdAt: Date()
        )
        do {
            try database.dbQueue.write { db in try record.insert(db) }
            reload()
            return subject(id: record.id)
        } catch {
            print("[PalaceStore] addSubject failed: \(error)")
            return nil
        }
    }

    func deleteSubject(id: String) {
        do {
            try database.dbQueue.write { db in
                let topicIds = try String.fetchAll(
                    db, sql: "SELECT id FROM topic WHERE subjectId = ?", arguments: [id]
                )
                var entryIds: [String] = []
                for topicId in topicIds {
                    entryIds += try String.fetchAll(
                        db, sql: "SELECT id FROM entry WHERE topicId = ?", arguments: [topicId]
                    )
                }
                try Self.cleanupDerivedData(db, entryIds: entryIds)
                _ = try SubjectRecord.deleteOne(db, key: id)
            }
            reload()
        } catch {
            print("[PalaceStore] deleteSubject failed: \(error)")
        }
    }

    @discardableResult
    func addTopic(subjectId: String, name: String) -> Topic? {
        let record = TopicRecord(
            id: UUID().uuidString,
            subjectId: subjectId,
            name: name,
            createdAt: Date()
        )
        do {
            try database.dbQueue.write { db in try record.insert(db) }
            reload()
            return subject(id: subjectId)?.topics.first { $0.id == record.id }
        } catch {
            print("[PalaceStore] addTopic failed: \(error)")
            return nil
        }
    }

    // MARK: - Entries

    @discardableResult
    func addEntry(
        topicId: String,
        question: String,
        learned: String,
        kind: EntryKind,
        toolName: String,
        outcome: Outcome,
        createdAt: Date = Date()
    ) -> Entry? {
        let record = EntryRecord(
            id: UUID().uuidString,
            topicId: topicId,
            question: question,
            learned: learned,
            kindRaw: kind.rawValue,
            toolName: toolName,
            outcomeRaw: outcome.rawValue,
            createdAt: createdAt
        )
        do {
            try database.dbQueue.write { db in
                try record.insert(db)
                try Self.refreshSearchRow(db, entryId: record.id)
            }
            reload()
            onEntryNeedsIndexing?(record.id)
            return entry(id: record.id)
        } catch {
            print("[PalaceStore] addEntry failed: \(error)")
            return nil
        }
    }

    func deleteEntry(id: String) {
        do {
            try database.dbQueue.write { db in
                try Self.cleanupDerivedData(db, entryIds: [id])
                _ = try EntryRecord.deleteOne(db, key: id)
            }
            reload()
        } catch {
            print("[PalaceStore] deleteEntry failed: \(error)")
        }
    }

    // MARK: - Attachments

    @discardableResult
    func addImageAttachment(entryId: String, data: Data, fileExtension: String = "jpg") -> Attachment? {
        let fileName = "att-\(UUID().uuidString).\(fileExtension)"
        let url = SharedContainer.attachmentsDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: url, options: .atomic)
            return insertAttachment(entryId: entryId, fileName: fileName, kind: .image)
        } catch {
            print("[PalaceStore] addImageAttachment failed: \(error)")
            return nil
        }
    }

    @discardableResult
    func addDocumentAttachment(entryId: String, sourceURL: URL) -> Attachment? {
        let ext = sourceURL.pathExtension.isEmpty ? "dat" : sourceURL.pathExtension
        let fileName = "att-\(UUID().uuidString).\(ext)"
        let destination = SharedContainer.attachmentsDirectory.appendingPathComponent(fileName)
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return insertAttachment(entryId: entryId, fileName: fileName, kind: .document)
        } catch {
            print("[PalaceStore] addDocumentAttachment failed: \(error)")
            return nil
        }
    }

    private func insertAttachment(entryId: String, fileName: String, kind: AttachmentKind) -> Attachment? {
        let record = AttachmentRecord(
            id: UUID().uuidString,
            entryId: entryId,
            fileName: fileName,
            kindRaw: kind.rawValue,
            ocrText: nil,
            caption: nil,
            createdAt: Date()
        )
        do {
            try database.dbQueue.write { db in try record.insert(db) }
            reload()
            onEntryNeedsIndexing?(entryId)
            return entry(id: entryId)?.attachments.first { $0.id == record.id }
        } catch {
            print("[PalaceStore] insertAttachment failed: \(error)")
            return nil
        }
    }

    /// Stores the OCR/caption produced by the vision pipeline and refreshes
    /// the entry's keyword index so attachment text becomes searchable.
    func updateAttachmentAnalysis(id: String, ocrText: String?, caption: String?) {
        do {
            var entryId: String?
            try database.dbQueue.write { db in
                guard var record = try AttachmentRecord.fetchOne(db, key: id) else { return }
                record.ocrText = ocrText
                record.caption = caption
                try record.update(db)
                try Self.refreshSearchRow(db, entryId: record.entryId)
                entryId = record.entryId
            }
            reload()
            if let entryId {
                onEntryNeedsIndexing?(entryId)
            }
        } catch {
            print("[PalaceStore] updateAttachmentAnalysis failed: \(error)")
        }
    }

    func deleteAttachment(id: String) {
        do {
            var entryId: String?
            try database.dbQueue.write { db in
                guard let record = try AttachmentRecord.fetchOne(db, key: id) else { return }
                entryId = record.entryId
                let url = SharedContainer.attachmentsDirectory
                    .appendingPathComponent(record.fileName)
                try? FileManager.default.removeItem(at: url)
                try db.execute(
                    sql: "DELETE FROM embedding WHERE ownerId = ?", arguments: [id]
                )
                _ = try AttachmentRecord.deleteOne(db, key: id)
                if let entryId {
                    try Self.refreshSearchRow(db, entryId: entryId)
                }
            }
            reload()
            if let entryId {
                onEntryNeedsIndexing?(entryId)
            }
        } catch {
            print("[PalaceStore] deleteAttachment failed: \(error)")
        }
    }

    // MARK: - Keyword search

    /// FTS5-backed keyword search resolved against the in-memory snapshot.
    func keywordSearch(_ query: String, limit: Int = 40) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        do {
            let matches = try database.dbQueue.read { db in
                try AppDatabase.keywordMatches(db, query: trimmed, limit: limit)
            }
            return matches.compactMap { entry(id: $0.entryId) }
        } catch {
            print("[PalaceStore] keywordSearch failed: \(error)")
            return []
        }
    }

    // MARK: - Ask history

    func recordAskExchange(question: String, answer: String, sourceIds: [String], engine: String) {
        let json = (try? JSONEncoder().encode(sourceIds)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? "[]"
        let record = AskExchangeRecord(
            id: UUID().uuidString,
            question: question,
            answer: answer,
            sourceIdsJSON: json,
            engine: engine,
            createdAt: Date()
        )
        do {
            try database.dbQueue.write { db in try record.insert(db) }
            reload()
        } catch {
            print("[PalaceStore] recordAskExchange failed: \(error)")
        }
    }

    func clearAskHistory() {
        do {
            try database.dbQueue.write { db in
                _ = try AskExchangeRecord.deleteAll(db)
            }
            reload()
        } catch {
            print("[PalaceStore] clearAskHistory failed: \(error)")
        }
    }

    // MARK: - Share-sheet inbox

    /// Pulls captures written by the share extension into real entries.
    func ingestSharedInbox() {
        let items = SharedInboxItem.pendingItems()
        guard !items.isEmpty else { return }
        for item in items {
            ingest(item)
            item.removeFromInbox()
        }
        reload()
    }

    private func ingest(_ item: SharedInboxItem) {
        let topicId = resolveTopic(for: item)
        guard let topicId else { return }

        let question = item.title.isEmpty ? "Captured from share sheet" : item.title
        var learned = item.text
        if let link = item.link, !link.isEmpty {
            learned = learned.isEmpty ? link : "\(learned)\n\(link)"
        }
        if learned.isEmpty { learned = question }

        guard let entry = addEntry(
            topicId: topicId,
            question: question,
            learned: learned,
            kind: .discovery,
            toolName: "Share Sheet",
            outcome: .worked,
            createdAt: item.createdAt
        ) else { return }

        let fm = FileManager.default
        for imageName in item.imageFileNames {
            let source = SharedContainer.inboxDirectory.appendingPathComponent(imageName)
            guard fm.fileExists(atPath: source.path) else { continue }
            if let data = try? Data(contentsOf: source) {
                _ = addImageAttachment(
                    entryId: entry.id,
                    data: data,
                    fileExtension: source.pathExtension.isEmpty ? "jpg" : source.pathExtension
                )
            }
            try? fm.removeItem(at: source)
        }
    }

    private func resolveTopic(for item: SharedInboxItem) -> String? {
        if let topicId = item.topicId,
           subjects.contains(where: { $0.topics.contains { $0.id == topicId } }) {
            return topicId
        }
        if let subjectId = item.subjectId, let subject = subject(id: subjectId) {
            let name = item.newTopicName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name, !name.isEmpty {
                return addTopic(subjectId: subjectId, name: name)?.id
            }
            if let inbox = subject.topics.first(where: { $0.name == "Inbox" }) {
                return inbox.id
            }
            return addTopic(subjectId: subjectId, name: "Inbox")?.id
                ?? subject.topics.first?.id
        }
        // Fall back to an "Inbox" subject.
        if let existing = subjects.first(where: { $0.name == "Inbox" }) {
            return existing.topics.first?.id
                ?? addTopic(subjectId: existing.id, name: "Inbox")?.id
        }
        guard let created = addSubject(
            name: "Inbox", symbolName: "tray.fill", colorRaw: SubjectColor.violet.rawValue
        ) else { return nil }
        return addTopic(subjectId: created.id, name: "Inbox")?.id
    }

    // MARK: - Catalog for the share extension

    private func writeCatalog() {
        let catalog = PalaceCatalog(
            subjects: subjects.map { subject in
                PalaceCatalog.SubjectSummary(
                    id: subject.id,
                    name: subject.name,
                    symbolName: subject.symbolName,
                    topics: subject.topics.map {
                        PalaceCatalog.TopicSummary(id: $0.id, name: $0.name)
                    }
                )
            }
        )
        catalog.save()
    }

    // MARK: - Shared cleanup helpers

    /// Removes FTS rows, embedding vectors, and attachment files for entries
    /// that are about to be deleted (row cascade handles the records).
    nonisolated private static func cleanupDerivedData(_ db: Database, entryIds: [String]) throws {
        guard !entryIds.isEmpty else { return }
        try AppDatabase.removeSearchText(db, entryIds: entryIds)
        for entryId in entryIds {
            let fileNames = try String.fetchAll(
                db, sql: "SELECT fileName FROM attachment WHERE entryId = ?", arguments: [entryId]
            )
            for fileName in fileNames {
                let url = SharedContainer.attachmentsDirectory.appendingPathComponent(fileName)
                try? FileManager.default.removeItem(at: url)
            }
            try db.execute(sql: "DELETE FROM embedding WHERE entryId = ?", arguments: [entryId])
        }
    }

    /// Rebuilds the FTS row for an entry, including topic/subject names and
    /// any attachment OCR/caption text.
    nonisolated static func refreshSearchRow(_ db: Database, entryId: String) throws {
        guard let entry = try EntryRecord.fetchOne(db, key: entryId) else { return }
        let topic = try TopicRecord.fetchOne(db, key: entry.topicId)
        let subject: SubjectRecord? =
            if let topic { try SubjectRecord.fetchOne(db, key: topic.subjectId) } else { nil }
        let attachments = try AttachmentRecord
            .filter(Column("entryId") == entryId)
            .fetchAll(db)

        var content = "\(entry.searchableText) \(topic?.name ?? "") \(subject?.name ?? "")"
        for attachment in attachments {
            if let caption = attachment.caption { content += " \(caption)" }
            if let ocr = attachment.ocrText { content += " \(ocr)" }
        }
        try AppDatabase.indexSearchText(db, entryId: entryId, content: content)
    }
}
