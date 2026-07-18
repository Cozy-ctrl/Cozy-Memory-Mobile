import Foundation

/// A single learning — the "drawer" of the palace. Stores the question you
/// had, the verbatim answer you found, which tool you used, and whether it worked.
/// Value snapshot assembled by `PalaceStore`; includes denormalized breadcrumb info.
nonisolated struct Entry: Identifiable, Hashable {
    let id: String
    var topicId: String
    var question: String
    var learned: String
    var kindRaw: String
    var toolName: String
    var outcomeRaw: String
    var createdAt: Date

    var topicName: String
    var subjectId: String
    var subjectName: String
    var subjectSymbol: String
    var subjectColorRaw: String

    var attachments: [Attachment]

    var kind: EntryKind {
        EntryKind(rawValue: kindRaw) ?? .fact
    }

    var outcome: Outcome {
        Outcome(rawValue: outcomeRaw) ?? .worked
    }

    var subjectAccent: SubjectColor {
        SubjectColor(rawValue: subjectColorRaw) ?? .cyan
    }

    /// Text used for semantic embedding of this entry.
    var embeddingText: String {
        var parts = ["Q: \(question)", "A: \(learned)", "Topic: \(subjectName) / \(topicName)"]
        for attachment in attachments {
            if let caption = attachment.caption, !caption.isEmpty {
                parts.append("Attachment: \(caption)")
            }
            if let ocr = attachment.ocrText, !ocr.isEmpty {
                parts.append("Attachment text: \(ocr)")
            }
        }
        return parts.joined(separator: "\n")
    }
}
