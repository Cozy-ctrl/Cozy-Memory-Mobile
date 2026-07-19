import SwiftUI
import UIKit

/// Research-tool leaderboard: which tools actually get you answers.
struct ToolsView: View {
    @Environment(PalaceStore.self) private var store

    private struct ExportItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    @State private var isExporting = false
    @State private var exportItem: ExportItem?
    @State private var exportError: String?

    private var stats: [ToolStat] {
        ToolStat.build(from: store.allEntries)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if stats.isEmpty {
                            emptyState
                        } else {
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

                        ownYourDataCard
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $exportItem) { item in
                ShareSheet(items: [item.url])
            }
            .alert(
                "Export failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                )
            ) {
                Button("OK") { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    private var ownYourDataCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.violet)
                Text("Own your data")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ice)
                Spacer()
            }
            Text("Export the whole palace — the database, every original photo and document, and a README explaining the formats — as a zip that's readable forever, with no app required.")
                .font(.caption)
                .foregroundStyle(Theme.muted)

            Button {
                exportPalace()
            } label: {
                HStack {
                    if isExporting {
                        ProgressView().tint(Theme.bg)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                    Text(isExporting ? "Preparing export…" : "Export palace")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(Theme.bg)
                .background(Theme.violet, in: .rect(cornerRadius: 10))
            }
            .disabled(isExporting)
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func exportPalace() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                let url = try PalaceExporter.export()
                exportItem = ExportItem(url: url)
            } catch {
                exportError = error.localizedDescription
            }
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

    /// Thin wrapper around `UIActivityViewController` for handing the
    /// exported zip to the system share sheet.
    private struct ShareSheet: UIViewControllerRepresentable {
        let items: [Any]

        func makeUIViewController(context: Context) -> UIActivityViewController {
            UIActivityViewController(activityItems: items, applicationActivities: nil)
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
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
