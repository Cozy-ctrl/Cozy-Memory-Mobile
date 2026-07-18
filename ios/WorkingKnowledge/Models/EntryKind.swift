import SwiftUI

/// Category of a learning entry — inspired by the source's "halls"
/// (facts, events, discoveries, preferences, advice).
enum EntryKind: String, CaseIterable, Identifiable {
    case fact
    case discovery
    case question
    case gotcha
    case advice

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fact: return "Fact"
        case .discovery: return "Discovery"
        case .question: return "Open Question"
        case .gotcha: return "Gotcha"
        case .advice: return "Advice"
        }
    }

    var symbol: String {
        switch self {
        case .fact: return "checkmark.seal.fill"
        case .discovery: return "sparkles"
        case .question: return "questionmark.circle.fill"
        case .gotcha: return "exclamationmark.triangle.fill"
        case .advice: return "lightbulb.fill"
        }
    }

    var color: Color {
        switch self {
        case .fact: return Theme.cyan
        case .discovery: return Theme.violet
        case .question: return Theme.warn
        case .gotcha: return Theme.hot
        case .advice: return Theme.ok
        }
    }
}
