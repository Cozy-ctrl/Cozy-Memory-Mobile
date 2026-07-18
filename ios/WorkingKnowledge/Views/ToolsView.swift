import SwiftUI

/// Research-tool leaderboard: which tools actually get you answers.
struct ToolsView: View {
    @Environment(PalaceStore.self) private var store

    private var stats: [ToolStat] {
        ToolStat.build(from: store.allEntries)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if stats.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("What actually works")
                                .font(.title3.weight(.bold))
                                .tracking(-0.3)
                                .foregroundStyle(Theme.heroGradient)

                            Text("Ranked by how often each tool got you a real answer.")
                                .font(.caption)
                                .foregroundStyle(Theme.muted)

                            VStack(spacing: 10) {
                                ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                                    toolRow(rank: index + 1, stat: stat)
                                }
                            }
                            .padding(.top, 4)
                        }
                        .padding(16)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func toolRow(rank: Int, stat: ToolStat) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text("#\(rank)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(rank == 1 ? Theme.warn : Theme.dim)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ice)
                    Text("\(stat.uses) use\(stat.uses == 1 ? "" : "s") · last \(stat.lastUsed.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                Text(stat.successRate.formatted(.percent.precision(.fractionLength(0))))
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(rateColor(stat.successRate))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.surfaceHigh)
                    Capsule()
                        .fill(Theme.cyanVioletGradient)
                        .frame(width: max(6, proxy.size.width * stat.successRate))
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(rank == 1 ? Theme.cyan.opacity(0.35) : Theme.border, lineWidth: 1)
        )
        .shadow(color: rank == 1 ? Theme.cyan.opacity(0.1) : .clear, radius: 10, y: 5)
    }

    private func rateColor(_ rate: Double) -> Color {
        if rate >= 0.75 { return Theme.ok }
        if rate >= 0.4 { return Theme.warn }
        return Theme.hot
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 36))
                .foregroundStyle(Theme.dim)
            Text("No tools tracked yet")
                .font(.headline)
                .foregroundStyle(Theme.body)
            Text("Every learning you capture records which tool\nyou used and whether it worked. Rankings\nshow up here automatically.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
    }
}
