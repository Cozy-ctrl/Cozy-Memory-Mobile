import Foundation

/// A subject you are learning — the "wing" of the palace.
/// Value snapshot assembled by `PalaceStore` from the database.
nonisolated struct Subject: Identifiable, Hashable {
    let id: String
    var name: String
    var symbolName: String
    var colorRaw: String
    var createdAt: Date
    var topics: [Topic]

    var accent: SubjectColor {
        SubjectColor(rawValue: colorRaw) ?? .cyan
    }

    var allEntries: [Entry] {
        topics.flatMap { $0.entries }
    }

    var lastActivity: Date? {
        allEntries.map { $0.createdAt }.max()
    }
}
