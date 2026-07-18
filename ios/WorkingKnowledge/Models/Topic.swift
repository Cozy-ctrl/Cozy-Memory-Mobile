import Foundation

/// A topic inside a subject — the "room" of the palace.
/// Value snapshot assembled by `PalaceStore` from the database.
nonisolated struct Topic: Identifiable, Hashable {
    let id: String
    var subjectId: String
    var name: String
    var createdAt: Date
    var entries: [Entry]
}
