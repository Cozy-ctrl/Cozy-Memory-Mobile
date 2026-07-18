import Foundation

/// Mirror of the app's shared-container contract. The extension writes
/// captures into the App Group inbox; the app ingests them on next launch.
/// Keep field names/coding in sync with the app target's `SharedContainer.swift`.
nonisolated enum SharedContainer {
    static let appGroupId = "group.app.rork.j7d3ui1nh64iiamhrvnfe"

    static var containerURL: URL {
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupId
        ) {
            return group
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    static var inboxDirectory: URL {
        containerURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    static var catalogURL: URL {
        containerURL.appendingPathComponent("catalog.json")
    }

    static func ensureDirectories() {
        try? FileManager.default.createDirectory(
            at: inboxDirectory, withIntermediateDirectories: true
        )
    }
}

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
}

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

    func save() throws {
        let data = try JSONEncoder().encode(self)
        let url = SharedContainer.inboxDirectory.appendingPathComponent("\(id).json")
        try data.write(to: url, options: .atomic)
    }
}
