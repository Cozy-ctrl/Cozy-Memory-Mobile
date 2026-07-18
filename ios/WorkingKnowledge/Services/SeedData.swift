import Foundation
import GRDB

/// Seeds a small example palace on first launch so the app never opens empty.
nonisolated enum SeedData {
    static func seedIfNeeded(database: AppDatabase) {
        do {
            try database.dbQueue.write { db in
                let count = try SubjectRecord.fetchCount(db)
                guard count == 0 else { return }

                let now = Date()
                let subject = SubjectRecord(
                    id: UUID().uuidString,
                    name: "Microcontrollers",
                    symbolName: "cpu",
                    colorRaw: SubjectColor.cyan.rawValue,
                    createdAt: now.addingTimeInterval(-86_400 * 6)
                )
                try subject.insert(db)

                let wiring = TopicRecord(
                    id: UUID().uuidString,
                    subjectId: subject.id,
                    name: "Power & Wiring",
                    createdAt: now.addingTimeInterval(-86_400 * 6)
                )
                let serial = TopicRecord(
                    id: UUID().uuidString,
                    subjectId: subject.id,
                    name: "Serial Communication",
                    createdAt: now.addingTimeInterval(-86_400 * 2)
                )
                try wiring.insert(db)
                try serial.insert(db)

                let entries: [EntryRecord] = [
                    EntryRecord(
                        id: UUID().uuidString,
                        topicId: wiring.id,
                        question: "Two black wires — which is ground and which is power?",
                        learned: "There is no universal standard for two black wires. Look for markings: a white stripe, ribbing, or printed text usually marks the neutral/ground conductor. When in doubt, verify with a multimeter in continuity mode against the device's ground plane before applying power.",
                        kindRaw: EntryKind.gotcha.rawValue,
                        toolName: "Google",
                        outcomeRaw: Outcome.worked.rawValue,
                        createdAt: now.addingTimeInterval(-86_400 * 5)
                    ),
                    EntryRecord(
                        id: UUID().uuidString,
                        topicId: wiring.id,
                        question: "What input voltage is safe for an ESP32 dev board?",
                        learned: "Power it with 5V via USB or the VIN pin — the onboard regulator drops it to 3.3V. Never feed 5V directly into GPIO pins; ESP32 pins are NOT 5V tolerant.",
                        kindRaw: EntryKind.fact.rawValue,
                        toolName: "ChatGPT",
                        outcomeRaw: Outcome.worked.rawValue,
                        createdAt: now.addingTimeInterval(-86_400 * 4)
                    ),
                    EntryRecord(
                        id: UUID().uuidString,
                        topicId: serial.id,
                        question: "Why is my serial monitor printing garbage characters?",
                        learned: "Baud rate mismatch. The rate in Serial.begin(115200) must match the monitor's setting exactly. Also check for a shared ground when using a separate USB-serial adapter.",
                        kindRaw: EntryKind.gotcha.rawValue,
                        toolName: "Stack Overflow",
                        outcomeRaw: Outcome.worked.rawValue,
                        createdAt: now.addingTimeInterval(-86_400 * 2)
                    ),
                ]

                for entry in entries {
                    try entry.insert(db)
                    try PalaceStore.refreshSearchRow(db, entryId: entry.id)
                }
            }
        } catch {
            print("[SeedData] seeding failed: \(error)")
        }
    }
}
