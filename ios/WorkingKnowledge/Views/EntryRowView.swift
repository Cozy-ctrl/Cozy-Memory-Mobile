import SwiftUI

/// Compact row for a learning entry inside lists and search results.
struct EntryRowView: View {
    let entry: Entry
    var showsBreadcrumb: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: entry.kind.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.kind.color)
                    .frame(width: 26, height: 26)
                    .background(entry.kind.color.opacity(0.13), in: .rect(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.question)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ice)
                        .lineLimit(2)

                    Text(entry.learned)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "wrench.adjustable")
                        .font(.system(size: 9))
                    Text(entry.toolName)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Theme.cyanLight)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Theme.cyan.opacity(0.1), in: .capsule)

                HStack(spacing: 4) {
                    Image(systemName: entry.outcome.symbol)
                        .font(.system(size: 9))
                    Text(entry.outcome.label)
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(entry.outcome.color)

                if !entry.attachments.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "paperclip")
                            .font(.system(size: 9))
                        Text("\(entry.attachments.count)")
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(Theme.violet)
                }

                Spacer()

                if showsBreadcrumb {
                    Text("\(entry.subjectName) › \(entry.topicName)")
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                } else {
                    Text(entry.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}
