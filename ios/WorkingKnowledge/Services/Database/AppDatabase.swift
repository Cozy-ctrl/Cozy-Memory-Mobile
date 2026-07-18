import Foundation
import GRDB

/// GRDB bootstrap: opens the shared SQLite database and runs migrations.
/// Holds entries, the FTS5 full-text index, and semantic embedding vectors
/// side by side — one local source of truth.
nonisolated final class AppDatabase: Sendable {
    static let shared = AppDatabase()

    let dbQueue: DatabaseQueue

    private init() {
        SharedContainer.ensureDirectories()
        do {
            dbQueue = try DatabaseQueue(path: SharedContainer.databaseURL.path)
            try Self.migrator.migrate(dbQueue)
        } catch {
            fatalError("Failed to open palace database: \(error)")
        }
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "subject") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("symbolName", .text).notNull()
                t.column("colorRaw", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "topic") { t in
                t.primaryKey("id", .text)
                t.column("subjectId", .text).notNull().indexed()
                    .references("subject", onDelete: .cascade)
                t.column("name", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "entry") { t in
                t.primaryKey("id", .text)
                t.column("topicId", .text).notNull().indexed()
                    .references("topic", onDelete: .cascade)
                t.column("question", .text).notNull()
                t.column("learned", .text).notNull()
                t.column("kindRaw", .text).notNull()
                t.column("toolName", .text).notNull()
                t.column("outcomeRaw", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "attachment") { t in
                t.primaryKey("id", .text)
                t.column("entryId", .text).notNull().indexed()
                    .references("entry", onDelete: .cascade)
                t.column("fileName", .text).notNull()
                t.column("kindRaw", .text).notNull()
                t.column("ocrText", .text)
                t.column("caption", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "embedding") { t in
                t.primaryKey("id", .text)
                t.column("entryId", .text).notNull().indexed()
                t.column("ownerKind", .text).notNull()
                t.column("ownerId", .text).notNull().indexed()
                t.column("model", .text).notNull()
                t.column("dim", .integer).notNull()
                t.column("vector", .blob).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "askExchange") { t in
                t.primaryKey("id", .text)
                t.column("question", .text).notNull()
                t.column("answer", .text).notNull()
                t.column("sourceIdsJSON", .text).notNull()
                t.column("engine", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(virtualTable: "entrySearch", using: FTS5()) { t in
                t.column("entryId")
                t.column("content")
            }
        }

        return migrator
    }

    // MARK: - FTS helpers

    /// Replaces the full-text index row for an entry.
    static func indexSearchText(_ db: Database, entryId: String, content: String) throws {
        try db.execute(sql: "DELETE FROM entrySearch WHERE entryId = ?", arguments: [entryId])
        try db.execute(
            sql: "INSERT INTO entrySearch (entryId, content) VALUES (?, ?)",
            arguments: [entryId, content]
        )
    }

    static func removeSearchText(_ db: Database, entryIds: [String]) throws {
        for id in entryIds {
            try db.execute(sql: "DELETE FROM entrySearch WHERE entryId = ?", arguments: [id])
        }
    }

    /// BM25-ranked full-text matches. Lower bm25 = better; returned score is
    /// normalized so that higher = better.
    static func keywordMatches(
        _ db: Database, query: String, limit: Int
    ) throws -> [(entryId: String, score: Double)] {
        guard
            let pattern = FTS5Pattern(matchingAllPrefixesIn: query)
                ?? FTS5Pattern(matchingAnyTokenIn: query)
        else { return [] }

        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT entryId, bm25(entrySearch) AS rank
                FROM entrySearch
                WHERE entrySearch MATCH ?
                ORDER BY rank
                LIMIT ?
                """,
            arguments: [pattern, limit]
        )
        return rows.map { row in
            let rank: Double = row["rank"] ?? 0
            return (entryId: row["entryId"] ?? "", score: -rank)
        }
    }
}
