import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Full view of one learning entry — the opened drawer, now with an
/// attachment gallery (photos + documents) read by the on-device AI.
struct EntryDetailView: View {
    @Environment(PalaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let entryId: String

    @State private var photoItem: PhotosPickerItem?
    @State private var isImportingFile: Bool = false
    @State private var previewAttachment: Attachment?

    private var entry: Entry? {
        store.entry(id: entryId)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            KindBadgeView(kind: entry.kind)
                            Spacer()
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Theme.dim)
                        }

                        Text(entry.question)
                            .font(.title2.weight(.bold))
                            .tracking(-0.4)
                            .foregroundStyle(Theme.ice)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Image(systemName: entry.subjectSymbol)
                                .font(.system(size: 11))
                            Text("\(entry.subjectName) › \(entry.topicName)")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(entry.subjectAccent.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(entry.subjectAccent.color.opacity(0.12), in: .capsule)

                        learnedCard(entry)
                        attachmentsCard(entry)
                        sourceCard(entry)
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Learning")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    store.deleteEntry(id: entryId)
                    dismiss()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.hot)
                }
            }
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    store.addImageAttachment(entryId: entryId, data: data)
                }
                photoItem = nil
            }
        }
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.pdf, .plainText, .image],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.addDocumentAttachment(entryId: entryId, sourceURL: url)
            }
        }
        .sheet(item: $previewAttachment) { attachment in
            AttachmentPreviewView(attachment: attachment)
        }
    }

    private func learnedCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("WHAT I LEARNED")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.dim)
                .tracking(0.8)

            Text(entry.learned)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(Theme.body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func attachmentsCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("ATTACHMENTS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.dim)
                    .tracking(0.8)
                Spacer()
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Add Photo", systemImage: "photo.badge.plus")
                    }
                    Button {
                        isImportingFile = true
                    } label: {
                        Label("Add File", systemImage: "doc.badge.plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                        Text("Add")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.cyan)
                }
            }

            if entry.attachments.isEmpty {
                Text("Attach wiring photos, datasheets, or screenshots — the on-device AI reads them so they show up in search and answers.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(entry.attachments) { attachment in
                        attachmentTile(attachment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 1)
        )
    }

    private func attachmentTile(_ attachment: Attachment) -> some View {
        Button {
            previewAttachment = attachment
        } label: {
            VStack(spacing: 6) {
                Color(Theme.surfaceHigh)
                    .frame(height: 76)
                    .overlay {
                        if attachment.kind == .image,
                           let image = UIImage(contentsOfFile: attachment.fileURL.path) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .allowsHitTesting(false)
                        } else {
                            Image(systemName: attachment.kind == .image ? "photo" : "doc.text")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(alignment: .bottomTrailing) {
                        if attachment.ocrText != nil || attachment.caption != nil {
                            Image(systemName: "sparkle")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Theme.bg)
                                .padding(4)
                                .background(Theme.cyan, in: .circle)
                                .padding(4)
                        }
                    }

                Text(attachment.displayName)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.deleteAttachment(id: attachment.id)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private func sourceCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SOURCE")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.dim)
                .tracking(0.8)

            HStack(spacing: 12) {
                Image(systemName: "wrench.adjustable.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.cyan)
                    .frame(width: 36, height: 36)
                    .background(Theme.cyan.opacity(0.12), in: .rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.toolName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ice)
                    Text("Research tool used")
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }

                Spacer()

                HStack(spacing: 5) {
                    Image(systemName: entry.outcome.symbol)
                        .font(.system(size: 12))
                    Text(entry.outcome.label)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(entry.outcome.color)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(entry.outcome.color.opacity(0.12), in: .capsule)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface, in: .rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

/// Full-screen look at one attachment plus everything the AI extracted from it.
private struct AttachmentPreviewView: View {
    let attachment: Attachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if attachment.kind == .image,
                       let image = UIImage(contentsOfFile: attachment.fileURL.path) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 14))
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 22))
                                .foregroundStyle(Theme.cyan)
                            Text(attachment.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ice)
                            Spacer()
                        }
                        .padding(14)
                        .background(Theme.surface, in: .rect(cornerRadius: 12))
                    }

                    if let caption = attachment.caption, !caption.isEmpty {
                        extractedBlock(title: "WHAT THE VISION MODEL SEES", text: caption)
                    }
                    if let ocr = attachment.ocrText, !ocr.isEmpty {
                        extractedBlock(title: "EXTRACTED TEXT", text: ocr)
                    }
                    if attachment.caption == nil && attachment.ocrText == nil {
                        Text("Not analyzed yet. Analysis runs automatically — OCR everywhere, vision captions once the Qwen3-VL model is downloaded on a real iPhone.")
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle("Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func extractedBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.dim)
                .tracking(0.8)
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.body)
                .lineSpacing(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 12))
    }
}
