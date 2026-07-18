import SwiftUI

/// Glowing card for one subject (wing) on the Palace home screen.
struct SubjectCardView: View {
    let subject: Subject

    private var entryCount: Int { subject.allEntries.count }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: subject.symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(subject.accent.color)
                .frame(width: 46, height: 46)
                .background(subject.accent.color.opacity(0.13), in: .rect(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(subject.accent.color.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.headline)
                    .foregroundStyle(Theme.ice)

                Text("\(subject.topics.count) topic\(subject.topics.count == 1 ? "" : "s") · \(entryCount) learning\(entryCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)

                if let last = subject.lastActivity {
                    Text("Last: \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 1)
        )
        .shadow(color: subject.accent.color.opacity(0.08), radius: 12, y: 6)
    }
}
