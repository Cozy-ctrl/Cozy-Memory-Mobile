import Foundation

/// Central place for on-disk locations shared between the app and the share
/// extension (App Group container), with a safe fallback for environments
/// where the group container is unavailable.
nonisolated enum SharedContainer {
    static let appGroupId = "group.app.rork.j7d3ui1nh64iiamhrvnfe"

    /// App Group container when entitled, otherwise Application Support.
    static var containerURL: URL {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            return group
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var databaseURL: URL {
        containerURL.appendingPathComponent("Palace", isDirectory: true)
            .appendingPathComponent("palace.sqlite")
    }

    static var attachmentsDirectory: URL {
        containerURL.appendingPathComponent("Attachments", isDirectory: true)
    }

    /// Items captured by the share extension, waiting to be ingested by the app.
    static var inboxDirectory: URL {
        containerURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    /// A lightweight snapshot of subjects/topics the share extension can read
    /// without linking the database.
    static var catalogURL: URL {
        containerURL.appendingPathComponent("catalog.json")
    }

    static func ensureDirectories() {
        let fm = FileManager.default
        for dir in [
            databaseURL.deletingLastPathComponent(),
            attachmentsDirectory,
            inboxDirectory,
        ] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Snapshot of the palace structure written by the app for the share extension.
nonisolated struct PalaceCatalog: Codable {
    struct SubjectSummary: Codable, Identifiable, Hashable {
        let id: String
        let name: String
        let symbolName: String
        let topics: [TopicSummary]
    }

    struct TopicSummary: Codable, Identifiable, Hashable {
        let id: String
        let name: String
    }

    let subjects: [SubjectSummary]

    static func load() -> PalaceCatalog? {
        guard let data = try? Data(contentsOf: SharedContainer.catalogURL) else { return nil }
        return try? JSONDecoder().decode(PalaceCatalog.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: SharedContainer.catalogURL, options: .atomic)
    }
}

/// One capture written by the share extension into the shared inbox.
nonisolated struct SharedInboxItem: Codable, Identifiable {
    let id: String
    var title: String
    var text: String
    var link: String?
    var subjectId: String?
    var topicId: String?
    var newTopicName: String?
    var imageFileNames: [String]
    var createdAt: Date

    static func pendingItems() -> [SharedInboxItem] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: SharedContainer.inboxDirectory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let decoder = JSONDecoder()
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(SharedInboxItem.self, from: data)
            }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func save() throws {
        let data = try JSONEncoder().encode(self)
        let url = SharedContainer.inboxDirectory.appendingPathComponent("\(id).json")
        try data.write(to: url, options: .atomic)
    }

    func removeFromInbox() {
        let fm = FileManager.default
        try? fm.removeItem(at: SharedContainer.inboxDirectory.appendingPathComponent("\(id).json"))
    }
}
