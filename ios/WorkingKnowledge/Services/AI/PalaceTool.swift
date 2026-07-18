import Foundation
import FoundationModels
import GRDB

/// Foundation Models tool conformance: lets Apple's on-device system model
/// query the palace. Used by the Ask tab's Apple Intelligence fallback and
/// available to any system AI session the app opens.
@available(iOS 26.0, *)
nonisolated struct PalaceSearchTool: Tool {
    let name = "searchPalace"
    let description =
        "Searches the user's personal knowledge base of saved learnings (questions they answered while learning) and returns the most relevant entries."

    @Generable
    nonisolated struct Arguments {
        @Guide(description: "The question or keywords to search the knowledge base for.")
        var query: String
    }

    func call(arguments: Arguments) async throws -> String {
        let results = Self.search(query: arguments.query, limit: 5)
        guard !results.isEmpty else {
            return "No saved learnings matched this query."
        }
        return results.enumerated()
            .map { index, item in
                "[\(index + 1)] Q: \(item.question)\nA: \(item.learned)\n(via \(item.toolName))"
            }
            .joined(separator: "\n\n")
    }

    private struct SearchResult {
        let question: String
        let learned: String
        let toolName: String
    }

    /// Direct FTS lookup against the shared database — safe from any context.
    private static func search(query: String, limit: Int) -> [SearchResult] {
        let matches = (try? AppDatabase.shared.dbQueue.read { db -> [SearchResult] in
            let hits = try AppDatabase.keywordMatches(db, query: query, limit: limit)
            return try hits.compactMap { hit in
                guard let record = try EntryRecord.fetchOne(db, key: hit.entryId) else {
                    return nil
                }
                return SearchResult(
                    question: record.question,
                    learned: record.learned,
                    toolName: record.toolName
                )
            }
        }) ?? []
        return matches
    }
}
