import AppIntents
import Foundation
import GRDB

/// Siri / Shortcuts entry point: "Ask Palace …". Runs a fast FTS lookup
/// against the shared database and speaks back the best saved learning.
struct AskPalaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Palace"
    static let description = IntentDescription(
        "Searches your Working Knowledge palace and returns the best saved answer."
    )

    @Parameter(title: "Question", requestValueDialog: "What do you want to ask your palace?")
    var question: String

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let matches = Self.search(query: question, limit: 3)

        guard let best = matches.first else {
            return .result(
                value: "",
                dialog: "Your palace has nothing on that yet. Capture it once you figure it out."
            )
        }

        let extraCount = matches.count - 1
        var spoken = best.learned
        if extraCount > 0 {
            spoken += " You have \(extraCount) more related learning\(extraCount == 1 ? "" : "s") in the app."
        }
        return .result(value: best.learned, dialog: IntentDialog(stringLiteral: spoken))
    }

    private struct Match {
        let question: String
        let learned: String
    }

    private static func search(query: String, limit: Int) -> [Match] {
        (try? AppDatabase.shared.dbQueue.read { db -> [Match] in
            let hits = try AppDatabase.keywordMatches(db, query: query, limit: limit)
            return try hits.compactMap { hit in
                guard let record = try EntryRecord.fetchOne(db, key: hit.entryId) else {
                    return nil
                }
                return Match(question: record.question, learned: record.learned)
            }
        }) ?? []
    }
}

struct PalaceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskPalaceIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask my \(.applicationName) palace",
                "Search \(.applicationName)",
            ],
            shortTitle: "Ask Palace",
            systemImageName: "brain.head.profile"
        )
    }
}
