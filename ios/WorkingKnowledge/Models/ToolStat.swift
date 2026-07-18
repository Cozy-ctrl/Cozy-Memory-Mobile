import Foundation

/// Aggregated effectiveness of a single research tool, derived from entries.
struct ToolStat: Identifiable {
    let name: String
    let uses: Int
    let successRate: Double
    let lastUsed: Date

    var id: String { name }

    /// Builds ranked tool stats from a list of entries.
    static func build(from entries: [Entry]) -> [ToolStat] {
        let grouped = Dictionary(grouping: entries) { $0.toolName }
        return grouped.map { name, group in
            let total = group.reduce(0.0) { $0 + $1.outcome.score }
            let last = group.map { $0.createdAt }.max() ?? Date.distantPast
            return ToolStat(
                name: name,
                uses: group.count,
                successRate: group.isEmpty ? 0 : total / Double(group.count),
                lastUsed: last
            )
        }
        .sorted { lhs, rhs in
            if lhs.uses != rhs.uses { return lhs.uses > rhs.uses }
            return lhs.successRate > rhs.successRate
        }
    }
}
