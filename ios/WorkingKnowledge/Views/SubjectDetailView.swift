import SwiftUI

/// One subject (wing): its topics (rooms) and the learnings filed in each.
struct SubjectDetailView: View {
    @Environment(PalaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let subjectId: String

    @State private var isCapturing: Bool = false
    @State private var isAddingTopic: Bool = false
    @State private var newTopicName: String = ""

    private var subject: Subject? {
        store.subject(id: subjectId)
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.bg.ignoresSafeArea()

            if let subject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        header(subject)

                        let sortedTopics = subject.topics.sorted { $0.createdAt < $1.createdAt }
                        if sortedTopics.isEmpty {
                            emptyState
                        } else {
                            ForEach(sortedTopics) { topic in
                                topicSection(topic, subject: subject)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }

                captureButton
            }
        }
        .navigationTitle(subject?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        isAddingTopic = true
                    } label: {
                        Label("New Topic", systemImage: "folder.badge.plus")
                    }
                    Button(role: .destructive) {
                        store.deleteSubject(id: subjectId)
                        dismiss()
                    } label: {
                        Label("Delete Subject", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isCapturing) {
            AddEntryView(preselectedSubjectId: subjectId, preselectedTopicId: nil)
        }
        .alert("New Topic", isPresented: $isAddingTopic) {
            TextField("e.g. Power & Wiring", text: $newTopicName)
            Button("Cancel", role: .cancel) { newTopicName = "" }
            Button("Add") { addTopic() }
        } message: {
            Text("A topic is a room in this wing — one focused area of \(subject?.name ?? "this subject").")
        }
    }

    private func header(_ subject: Subject) -> some View {
        HStack(spacing: 14) {
            Image(systemName: subject.symbolName)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(subject.accent.color)
                .frame(width: 56, height: 56)
                .background(subject.accent.color.opacity(0.13), in: .rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(subject.accent.color.opacity(0.3), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(subject.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.ice)
                Text("\(subject.topics.count) topics · \(subject.allEntries.count) learnings")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            Spacer()
        }
        .padding(.top, 12)
    }

    private func topicSection(_ topic: Topic, subject: Subject) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "square.split.bottomrightquarter")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(subject.accent.color)
                Text(topic.name.uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.body)
                    .tracking(0.6)
                Spacer()
                Text("\(topic.entries.count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.dim)
            }

            if topic.entries.isEmpty {
                Text("Nothing filed here yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Theme.surface.opacity(0.5), in: .rect(cornerRadius: 12))
            } else {
                VStack(spacing: 10) {
                    ForEach(topic.entries.sorted { $0.createdAt > $1.createdAt }) { entry in
                        NavigationLink(value: entry) {
                            EntryRowView(entry: entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.split.bottomrightquarter")
                .font(.system(size: 32))
                .foregroundStyle(Theme.dim)
            Text("No topics yet")
                .font(.headline)
                .foregroundStyle(Theme.body)
            Text("Capture your first learning and a topic\nwill be created along the way.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var captureButton: some View {
        Button {
            isCapturing = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .semibold))
                Text("Capture")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Theme.cyanVioletGradient, in: .capsule)
            .shadow(color: Theme.cyan.opacity(0.35), radius: 14, y: 6)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 16)
    }

    private func addTopic() {
        let trimmed = newTopicName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addTopic(subjectId: subjectId, name: trimmed)
        newTopicName = ""
    }
}
