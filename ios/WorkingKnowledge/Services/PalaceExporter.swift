import Foundation

/// "Own your data": bundles the whole palace — database, original
/// attachments, and a README explaining both — into a single zip a person
/// can open with nothing but a text editor and a SQLite browser, forever,
/// even if this app disappears. Built after the Rewind story (a memory app
/// whose users lost their entire archive when the company shut it down) —
/// the promise this button keeps is "readable forever, no app required."
nonisolated enum PalaceExporter {
    enum ExportError: LocalizedError {
        case checkpointFailed
        case zipFailed

        var errorDescription: String? {
            switch self {
            case .checkpointFailed: return "Couldn't prepare the database for export."
            case .zipFailed: return "Couldn't package the export."
            }
        }
    }

    /// Builds a self-contained zip in a temporary directory and returns its
    /// URL, ready to hand to a share sheet. Caller is responsible for
    /// cleaning up the returned file once it's been presented/shared.
    static func export(database: AppDatabase = .shared) throws -> URL {
        // 1. Checkpoint the write-ahead log so the .sqlite file is
        //    self-complete — without this, any writes still sitting in the
        //    -wal file wouldn't be visible to a plain SQLite reader that
        //    only receives the .sqlite file itself.
        do {
            try database.dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
            }
        } catch {
            throw ExportError.checkpointFailed
        }

        let fm = FileManager.default
        let workDir = fm.temporaryDirectory.appendingPathComponent(
            "PalaceExport-\(UUID().uuidString)", isDirectory: true
        )
        let bundleDir = workDir.appendingPathComponent("WorkingKnowledgePalace", isDirectory: true)
        try fm.createDirectory(at: bundleDir, withIntermediateDirectories: true)

        // 2. Copy the database.
        try fm.copyItem(
            at: SharedContainer.databaseURL,
            to: bundleDir.appendingPathComponent("palace.sqlite")
        )

        // 3. Copy every original attachment file, unmodified.
        let attachmentsDestination = bundleDir.appendingPathComponent("Attachments", isDirectory: true)
        if fm.fileExists(atPath: SharedContainer.attachmentsDirectory.path) {
            try fm.copyItem(at: SharedContainer.attachmentsDirectory, to: attachmentsDestination)
        }

        // 4. Explain the formats in plain text.
        try readmeText.write(
            to: bundleDir.appendingPathComponent("README.txt"),
            atomically: true,
            encoding: .utf8
        )

        // 5. Zip the bundle with no third-party dependency: passing
        //    `.forUploading` to NSFileCoordinator asks the system to produce
        //    a temporary zip archive of the item — the same mechanism iOS
        //    uses to upload a document to iCloud Drive or attach a folder to
        //    Mail, repurposed here to avoid shipping a zip library.
        let zipURL = try zip(directory: bundleDir, in: workDir)
        return zipURL
    }

    private static func zip(directory: URL, in workDir: URL) throws -> URL {
        var resultURL: URL?
        var coordinatorError: Error?
        let coordinator = NSFileCoordinator()
        let intent = NSFileAccessIntent.readingIntent(with: directory, options: [.forUploading])
        let group = DispatchGroup()
        group.enter()
        coordinator.coordinate(with: [intent], queue: .init()) { error in
            defer { group.leave() }
            if let error {
                coordinatorError = error
                return
            }
            resultURL = intent.url
        }
        group.wait()

        if let coordinatorError { throw coordinatorError }
        guard let zippedURL = resultURL else { throw ExportError.zipFailed }

        // The coordinator hands back a temporary zip owned by the system;
        // move it somewhere this app controls before handing it to a share
        // sheet (the temporary location can be cleaned up at any time).
        let destination = workDir.deletingLastPathComponent()
            .appendingPathComponent("WorkingKnowledgePalace-\(dateStamp()).zip")
        try FileManager.default.copyItem(at: zippedURL, to: destination)
        return destination
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static let readmeText = """
        Working Knowledge — Palace Export
        ==================================

        This zip is your entire palace, in formats that will outlive this app.

        palace.sqlite
        -------------
        A standard SQLite 3 database. Open it with any SQLite browser (DB
        Browser for SQLite, the `sqlite3` command line tool, etc.) — no
        Working Knowledge install required. Tables of interest:
          - subject, topic, entry: your learnings, organized the way you saw them.
          - attachment: metadata for each photo/document, including any
            on-device OCR text captured for it.
          - embedding: the semantic vectors used for search. Each row records
            which model produced it (see the "model" column) — vectors from
            different models are not comparable to each other.
          - askExchange: your Ask Palace question/answer history.

        Attachments/
        ------------
        Every photo and document you attached, as the original files —
        untouched, at full resolution, under their original file names.

        Nothing in this export requires Working Knowledge, MLX, or any
        specific app to read. If this app is ever gone, this zip is still
        your knowledge.
        """
}
