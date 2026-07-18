import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Quick capture sheet: files shared text, links, or images into the palace
/// inbox with a subject/topic picker fed by the app's catalog snapshot.
struct ShareView: View {
    let extensionContext: NSExtensionContext?

    @State private var payload = SharedPayload()
    @State private var isLoading = true
    @State private var catalog: PalaceCatalog?
    @State private var selectedSubjectId: String?
    @State private var selectedTopicId: String?
    @State private var title: String = ""
    @State private var didSave = false

    // Crystal Lattice palette (mirrored from the app).
    private let bg = Color(red: 8 / 255, green: 12 / 255, blue: 24 / 255)
    private let surface = Color(red: 15 / 255, green: 21 / 255, blue: 36 / 255)
    private let border = Color(red: 28 / 255, green: 38 / 255, blue: 64 / 255)
    private let cyan = Color(red: 56 / 255, green: 189 / 255, blue: 248 / 255)
    private let violet = Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255)
    private let ice = Color(red: 219 / 255, green: 231 / 255, blue: 245 / 255)
    private let muted = Color(red: 139 / 255, green: 153 / 255, blue: 176 / 255)
    private let dim = Color(red: 91 / 255, green: 107 / 255, blue: 130 / 255)

    private var selectedSubject: PalaceCatalog.SubjectSummary? {
        catalog?.subjects.first { $0.id == selectedSubjectId }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                bg.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(cyan)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            previewCard
                            titleField
                            subjectPicker
                            topicPicker
                            Text("Filed into your palace inbox — it becomes a searchable learning next time you open the app.")
                                .font(.caption2)
                                .foregroundStyle(dim)
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Save to Palace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        extensionContext?.completeRequest(returningItems: nil)
                    }
                    .foregroundStyle(muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("File It") { save() }
                        .fontWeight(.bold)
                        .foregroundStyle(cyan)
                        .disabled(didSave || (payload.isEmpty && title.isEmpty))
                }
            }
        }
        .preferredColorScheme(.dark)
        .task {
            SharedContainer.ensureDirectories()
            catalog = PalaceCatalog.load()
            selectedSubjectId = catalog?.subjects.first?.id
            payload = await SharePayloadLoader.load(from: extensionContext)
            if title.isEmpty {
                title = payload.suggestedTitle
            }
            isLoading = false
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(dim)
            .tracking(0.8)
    }

    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("SHARED CONTENT")

            if !payload.imageDatas.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(payload.imageDatas.enumerated()), id: \.offset) { _, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(.rect(cornerRadius: 10))
                            }
                        }
                    }
                }
            }

            if let link = payload.link {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 11))
                    Text(link)
                        .font(.caption)
                        .lineLimit(1)
                }
                .foregroundStyle(cyan)
            }

            if !payload.text.isEmpty {
                Text(payload.text)
                    .font(.caption)
                    .foregroundStyle(muted)
                    .lineLimit(4)
            }

            if payload.isEmpty {
                Text("Nothing readable was shared — add a note below.")
                    .font(.caption)
                    .foregroundStyle(dim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(surface, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(border, lineWidth: 1))
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("WHAT IS THIS ABOUT?")
            TextField("Give it a searchable title…", text: $title, axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline)
                .foregroundStyle(ice)
                .padding(12)
                .background(surface, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(border, lineWidth: 1))
        }
    }

    @ViewBuilder
    private var subjectPicker: some View {
        if let catalog, !catalog.subjects.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                label("SUBJECT")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(catalog.subjects) { subject in
                            chip(
                                text: subject.name,
                                symbol: subject.symbolName,
                                isSelected: selectedSubjectId == subject.id
                            ) {
                                selectedSubjectId = subject.id
                                selectedTopicId = nil
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var topicPicker: some View {
        if let subject = selectedSubject, !subject.topics.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                label("TOPIC")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        chip(text: "Inbox", symbol: "tray", isSelected: selectedTopicId == nil) {
                            selectedTopicId = nil
                        }
                        ForEach(subject.topics) { topic in
                            chip(text: topic.name, symbol: nil, isSelected: selectedTopicId == topic.id) {
                                selectedTopicId = topic.id
                            }
                        }
                    }
                }
            }
        }
    }

    private func chip(
        text: String, symbol: String?, isSelected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(text)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? cyan : muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? cyan.opacity(0.13) : surface, in: .capsule)
            .overlay(
                Capsule().stroke(isSelected ? cyan.opacity(0.5) : border, lineWidth: 1)
            )
        }
    }

    private func save() {
        guard !didSave else { return }
        didSave = true

        SharedContainer.ensureDirectories()
        var imageNames: [String] = []
        for data in payload.imageDatas.prefix(6) {
            let name = "share-\(UUID().uuidString).jpg"
            let url = SharedContainer.inboxDirectory.appendingPathComponent(name)
            if (try? data.write(to: url, options: .atomic)) != nil {
                imageNames.append(name)
            }
        }

        let item = SharedInboxItem(
            id: UUID().uuidString,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            text: payload.text,
            link: payload.link,
            subjectId: selectedSubjectId,
            topicId: selectedTopicId,
            newTopicName: nil,
            imageFileNames: imageNames,
            createdAt: Date()
        )
        try? item.save()

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        extensionContext?.completeRequest(returningItems: nil)
    }
}

// MARK: - Payload extraction

struct SharedPayload {
    var title: String = ""
    var text: String = ""
    var link: String?
    var imageDatas: [Data] = []

    var isEmpty: Bool {
        text.isEmpty && link == nil && imageDatas.isEmpty
    }

    var suggestedTitle: String {
        if !title.isEmpty { return title }
        if !text.isEmpty { return String(text.prefix(80)) }
        if let link { return link }
        if !imageDatas.isEmpty { return "Shared photo" }
        return ""
    }
}

nonisolated enum SharePayloadLoader {
    static func load(from context: NSExtensionContext?) async -> SharedPayload {
        var payload = SharedPayload()
        let items = context?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []

        for item in items {
            if payload.title.isEmpty, let attributed = item.attributedTitle {
                payload.title = attributed.string
            }
            if payload.text.isEmpty, let attributed = item.attributedContentText {
                payload.text = attributed.string
            }

            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
                   payload.link == nil {
                    payload.link = (await loadURL(from: provider))?.absoluteString
                } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let data = await loadImageData(from: provider) {
                        payload.imageDatas.append(data)
                    }
                } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                          payload.text.isEmpty {
                    payload.text = (await loadText(from: provider)) ?? ""
                }
            }
        }
        return payload
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private static func loadText(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
