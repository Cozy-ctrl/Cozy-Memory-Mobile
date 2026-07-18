import SwiftUI

/// How well the research tool answered the question for a given entry.
enum Outcome: String, CaseIterable, Identifiable {
    case worked
    case partial
    case failed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worked: return "Worked"
        case .partial: return "Partially"
        case .failed: return "Didn't work"
        }
    }

    var symbol: String {
        switch self {
        case .worked: return "checkmark.circle.fill"
        case .partial: return "minus.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .worked: return Theme.ok
        case .partial: return Theme.warn
        case .failed: return Theme.hot
        }
    }

    /// Score used to compute a tool's effectiveness rate.
    var score: Double {
        switch self {
        case .worked: return 1.0
        case .partial: return 0.5
        case .failed: return 0.0
        }
    }
}
