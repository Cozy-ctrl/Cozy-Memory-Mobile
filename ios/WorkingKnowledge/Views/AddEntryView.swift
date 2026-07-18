import PhotosUI
import SwiftUI

/// Capture composer — files a new learning into a subject's topic,
/// optionally with photo attachments that get indexed by the AI pipeline.
struct AddEntryView: View {
    @Environment(PalaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let preselectedSubjectId: String?
    let preselectedTopicId: String?

    @State private var selectedSubjectId: String?
    @State private var selectedTopicId: String?
    @State private var isCreatingTopic: Bool = false
    @State private var newTopicName: String = ""
    @State private var question: String = ""
    @State private var learned: String = ""
    @State private var kind: EntryKind = .fact
    @State private var selectedTool: String = "Google"
    @State private var isCustomTool: Bool = false
    @State private var customTool: String = ""
    @State private var outcome: Outcome = .worked
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var photoDatas: [Data] = []

    private var selectedSubject: Subject? {
        store.subjects.first { $0.id == selectedSubjectId }
    }

    private var resolvedTool: String {
        isCustomTool ? customTool.trimmingCharacters(in: .whitespacesAndNewlines) : selectedTool
    }

    private var topicsForSubject: [Topic] {
        (selectedSubject?.topics ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    private var canSave: Bool {
        guard selectedSubjectId != nil else { return false }
        let hasTopic = (selectedTopicId != nil && !isCreatingTopic)
            || !newTopicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasTopic
            && !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !learned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !resolvedTool.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    subjectSection
                    topicSection
                    questionSection
                    learnedSection
                    photosSection
                    kindSection
                    toolSection
                    outcomeSection
                }
                .padding(20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            .presentationBackground(Theme.bg)
            .navigationTitle("Capture Learning")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("File It") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .onAppear {
                if selectedSubjectId == nil {
                    selectedSubjectId = preselectedSubjectId ?? store.subjects.first?.id
                }
                if selectedTopicId == nil {
                    selectedTopicId = preselectedTopicId ?? topicsForSubject.first?.id
                }
                if topicsForSubject.isEmpty {
                    isCreatingTopic = true
                }
            }
            .onChange(of: photoItems) { _, newItems in
                Task {
                    var datas: [Data] = []
                    for item in newItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            datas.append(data)
                        }
                    }
                    photoDatas = datas
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Theme.dim)
            .tracking(0.8)
    }

    private var subjectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("SUBJECT")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(store.subjects) { subject in
                        chip(
                            label: subject.name,
                            symbol: subject.symbolName,
                            isSelected: selectedSubjectId == subject.id,
                            tint: subject.accent.color
                        ) {
                            selectedSubjectId = subject.id
                            selectedTopicId = subject.topics
                                .sorted { $0.createdAt < $1.createdAt }
                                .first?.id
                            isCreatingTopic = selectedTopicId == nil
                        }
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    private var topicSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TOPIC")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(topicsForSubject) { topic in
                        chip(
                            label: topic.name,
                            symbol: nil,
                            isSelected: !isCreatingTopic && selectedTopicId == topic.id,
                            tint: Theme.cyan
                        ) {
                            selectedTopicId = topic.id
                            isCreatingTopic = false
                        }
                    }
                    chip(
                        label: "New topic",
                        symbol: "plus",
                        isSelected: isCreatingTopic,
                        tint: Theme.violet
                    ) {
                        isCreatingTopic = true
                        selectedTopicId = nil
                    }
                }
            }

            if isCreatingTopic {
                TextField("Topic name, e.g. Power & Wiring", text: $newTopicName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ice)
                    .padding(12)
                    .background(Theme.surface, in: .rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.violet.opacity(0.4), lineWidth: 1)
                    )
            }
        }
    }

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WHAT DID YOU NEED TO FIGURE OUT?")
            TextField("e.g. Which black wire is ground?", text: $question, axis: .vertical)
                .lineLimit(2...4)
                .font(.subheadline)
                .foregroundStyle(Theme.ice)
                .padding(12)
                .background(Theme.surface, in: .rect(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.border, lineWidth: 1)
                )
        }
    }

    private var learnedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("WHAT DID YOU LEARN? (VERBATIM)")
            TextField(
                "Write it exactly as you'd want to re-read it on your next project…",
                text: $learned,
                axis: .vertical
            )
            .lineLimit(4...10)
            .font(.system(.subheadline, design: .monospaced))
            .foregroundStyle(Theme.body)
            .padding(12)
            .background(Theme.surface, in: .rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("PHOTOS (OPTIONAL)")
            HStack(spacing: 10) {
                PhotosPicker(
                    selection: $photoItems,
                    maxSelectionCount: 4,
                    matching: .images
                ) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 13, weight: .semibold))
                        Text(photoDatas.isEmpty ? "Attach photos" : "\(photoDatas.count) attached")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(Theme.violet)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.violet.opacity(0.12), in: .capsule)
                    .overlay(Capsule().stroke(Theme.violet.opacity(0.4), lineWidth: 1))
                }

                if !photoDatas.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(photoDatas.enumerated()), id: \.offset) { _, data in
                                if let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 40, height: 40)
                                        .clipShape(.rect(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }
            Text("Photos are read on-device (OCR + vision model) so they become searchable.")
                .font(.caption2)
                .foregroundStyle(Theme.dim)
        }
    }

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("KIND")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EntryKind.allCases) { option in
                        chip(
                            label: option.label,
                            symbol: option.symbol,
                            isSelected: kind == option,
                            tint: option.color
                        ) {
                            kind = option
                        }
                    }
                }
            }
        }
    }

    private var toolSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TOOL YOU USED")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(ResearchTools.known, id: \.self) { tool in
                    chip(
                        label: tool,
                        symbol: nil,
                        isSelected: !isCustomTool && selectedTool == tool,
                        tint: Theme.cyan
                    ) {
                        selectedTool = tool
                        isCustomTool = false
                    }
                }
                chip(
                    label: "Other…",
                    symbol: "plus",
                    isSelected: isCustomTool,
                    tint: Theme.violet
                ) {
                    isCustomTool = true
                }
            }

            if isCustomTool {
                TextField("Tool name", text: $customTool)
                    .font(.subheadline)
                    .foregroundStyle(Theme.ice)
                    .padding(12)
                    .background(Theme.surface, in: .rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.violet.opacity(0.4), lineWidth: 1)
                    )
            }
        }
    }

    private var outcomeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DID IT WORK?")
            HStack(spacing: 8) {
                ForEach(Outcome.allCases) { option in
                    Button {
                        outcome = option
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 12))
                            Text(option.label)
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(outcome == option ? option.color : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            outcome == option ? option.color.opacity(0.13) : Theme.surface,
                            in: .rect(cornerRadius: 10)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    outcome == option ? option.color.opacity(0.45) : Theme.border,
                                    lineWidth: 1
                                )
                        )
                    }
                }
            }
        }
    }

    private func chip(
        label: String,
        symbol: String?,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? tint : Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? tint.opacity(0.13) : Theme.surface, in: .capsule)
            .overlay(
                Capsule().stroke(isSelected ? tint.opacity(0.5) : Theme.border, lineWidth: 1)
            )
        }
    }

    private func save() {
        guard let subjectId = selectedSubjectId else { return }

        let topicId: String?
        if let existing = selectedTopicId, !isCreatingTopic {
            topicId = existing
        } else {
            let name = newTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
            topicId = store.addTopic(subjectId: subjectId, name: name)?.id
        }
        guard let topicId else { return }

        let entry = store.addEntry(
            topicId: topicId,
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            learned: learned.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            toolName: resolvedTool,
            outcome: outcome
        )

        if let entry {
            for data in photoDatas {
                store.addImageAttachment(entryId: entry.id, data: data)
            }
        }

        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
