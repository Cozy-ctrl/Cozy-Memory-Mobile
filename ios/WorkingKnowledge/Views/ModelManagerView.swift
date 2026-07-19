import SwiftUI

/// Settings sheet for the four on-device models: download state, storage,
/// per-model controls, and the semantic index status.
struct ModelManagerView: View {
    @Environment(ModelManager.self) private var models
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !AIAvailability.isOnDeviceSupported {
                        simulatorNotice
                    }

                    summaryCard

                    VStack(spacing: 12) {
                        ForEach(ModelCatalog.all) { spec in
                            modelCard(spec)
                        }
                    }

                    indexCard

                    Text("Models download once from Hugging Face (Wi-Fi recommended) and run entirely on this device. Nothing you capture or ask ever leaves your iPhone.")
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                        .padding(.top, 4)
                }
                .padding(16)
                .padding(.bottom, 24)
            }
            .background(Theme.bg)
            .navigationTitle("On-Device AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                models.refreshDiskState()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var simulatorNotice: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 18))
                .foregroundStyle(Theme.warn)
            Text(AIAvailability.simulatorNotice)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.warn.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.warn.opacity(0.3), lineWidth: 1)
        )
    }

    private var summaryCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("The answer pipeline")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.ice)
                Text("Embed → retrieve → rerank → synthesize, fully local.")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                Text("On disk: \(ByteCountFormatter.string(fromByteCount: models.totalBytesOnDisk, countStyle: .file))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Theme.cyan)
                    .padding(.top, 2)
            }
            Spacer()
            Button {
                models.downloadAll()
            } label: {
                Text("Get All")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.cyanVioletGradient, in: .capsule)
            }
            .disabled(!AIAvailability.isOnDeviceSupported || models.isAnyBusy)
            .opacity(AIAvailability.isOnDeviceSupported ? 1 : 0.4)
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func modelCard(_ spec: ModelSpec) -> some View {
        let phase = models.phase(for: spec.role)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: spec.role.symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.violet)
                    .frame(width: 38, height: 38)
                    .background(Theme.violet.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(spec.role.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ice)
                    Text(spec.hubId)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }

                Spacer()

                controlButton(spec, phase: phase)
            }

            Text(spec.role.purpose)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if case .downloading(let fraction) = phase {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: fraction)
                        .tint(Theme.cyan)
                    Text("\(Int(fraction * 100))% of ~\(ByteCountFormatter.string(fromByteCount: spec.approxBytes, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            } else if case .failed(let message) = phase {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Theme.hot)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(spacing: 8) {
                    statusPill(phase)
                    Text(sizeLabel(spec, phase: phase))
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(phase == .ready ? Theme.ok.opacity(0.35) : Theme.border, lineWidth: 1)
        )
        .contextMenu {
            if phase == .ready || phase == .downloaded {
                Button(role: .destructive) {
                    models.delete(spec.role)
                } label: {
                    Label("Delete Download", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func controlButton(_ spec: ModelSpec, phase: ModelManager.Phase) -> some View {
        switch phase {
        case .notDownloaded, .failed:
            Button {
                models.activate(spec.role)
            } label: {
                Image(systemName: phase == .notDownloaded ? "arrow.down.circle.fill" : "arrow.clockwise.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.cyan)
            }
            .disabled(!AIAvailability.isOnDeviceSupported)
            .opacity(AIAvailability.isOnDeviceSupported ? 1 : 0.4)
        case .downloading, .loading:
            ProgressView()
                .tint(Theme.cyan)
        case .downloaded:
            Button {
                models.activate(spec.role)
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.violet)
            }
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.ok)
        }
    }

    private func statusPill(_ phase: ModelManager.Phase) -> some View {
        let (label, color): (String, Color) = switch phase {
        case .notDownloaded: ("Not downloaded", Theme.dim)
        case .downloading: ("Downloading", Theme.cyan)
        case .downloaded: ("On disk", Theme.violet)
        case .loading: ("Loading", Theme.cyan)
        case .ready: ("Ready", Theme.ok)
        case .failed: ("Failed", Theme.hot)
        }
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: .capsule)
    }

    private func sizeLabel(_ spec: ModelSpec, phase: ModelManager.Phase) -> String {
        let bytes = models.bytesOnDisk[spec.role] ?? 0
        if bytes > 0 {
            return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }
        return "~\(ByteCountFormatter.string(fromByteCount: spec.approxBytes, countStyle: .file))"
    }

    private var indexCard: some View {
        let unindexed = models.indexing?.unindexedCount ?? 0
        let stale = models.indexing?.staleVectorCount ?? 0
        let canReindex = models.embedding.isReady || models.imageEmbedding.isReady
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Semantic index")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ice)
                    Text(unindexed == 0
                         ? "Every learning has a meaning vector."
                         : "\(unindexed) learning\(unindexed == 1 ? "" : "s") waiting for a vector.")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                if models.indexing?.isIndexing == true {
                    ProgressView()
                        .tint(Theme.cyan)
                } else {
                    Button {
                        Task { await models.indexing?.reindexAll(force: true) }
                    } label: {
                        Text("Reindex")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.cyan)
                    }
                    .disabled(!canReindex)
                    .opacity(canReindex ? 1 : 0.4)
                }
            }
            if stale > 0 {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Theme.hot)
                    Text("\(stale) vector\(stale == 1 ? "" : "s") were made by a model you've since swapped out — they won't match anything until you reindex.")
                        .font(.caption2)
                        .foregroundStyle(Theme.hot)
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
