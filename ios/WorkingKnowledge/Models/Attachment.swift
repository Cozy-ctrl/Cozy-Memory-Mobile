import Foundation

nonisolated enum AttachmentKind: String {
    case image
    case document
}

/// A photo or document attached to a learning entry. The binary lives in the
/// shared attachments directory; the vision/OCR pipeline fills `ocrText`/`caption`.
nonisolated struct Attachment: Identifiable, Hashable {
    let id: String
    var entryId: String
    var fileName: String
    var kindRaw: String
    var ocrText: String?
    var caption: String?
    var createdAt: Date

    var kind: AttachmentKind {
        AttachmentKind(rawValue: kindRaw) ?? .document
    }

    var fileURL: URL {
        SharedContainer.attachmentsDirectory.appendingPathComponent(fileName)
    }

    var displayName: String {
        kind == .image ? "Photo" : (fileName as NSString).lastPathComponent
    }
}
