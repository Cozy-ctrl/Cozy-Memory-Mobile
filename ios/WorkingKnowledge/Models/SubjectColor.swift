import SwiftUI

/// Accent colors a subject (wing) can be tagged with.
enum SubjectColor: String, CaseIterable, Identifiable {
    case cyan
    case violet
    case green
    case amber
    case coral

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .cyan: return Theme.cyan
        case .violet: return Theme.violet
        case .green: return Theme.ok
        case .amber: return Theme.warn
        case .coral: return Theme.hot
        }
    }
}
