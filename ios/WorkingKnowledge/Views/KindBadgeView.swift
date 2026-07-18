import SwiftUI

/// Small colored capsule showing an entry's category.
struct KindBadgeView: View {
    let kind: EntryKind

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text(kind.label)
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(kind.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(kind.color.opacity(0.14), in: .capsule)
        .overlay(Capsule().stroke(kind.color.opacity(0.3), lineWidth: 1))
    }
}
