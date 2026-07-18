import SwiftUI

/// Home screen — the palace. Lists all subjects (wings) with a capture FAB.
struct SubjectsView: View {
    @Environment(PalaceStore.self) private var store

    @State private var isAddingSubject: Bool = false
    @State private var isCapturing: Bool = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header

                        if store.subjects.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(store.subjects) { subject in
                                    NavigationLink(value: subject) {
                                        SubjectCardView(subject: subject)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            store.deleteSubject(id: subject.id)
                                        } label: {
                                            Label("Delete Subject", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }

                captureButton
            }
            .navigationTitle("Palace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingSubject = true
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
            .navigationDestination(for: Subject.self) { subject in
                SubjectDetailView(subjectId: subject.id)
            }
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entryId: entry.id)
            }
            .sheet(isPresented: $isAddingSubject) {
                AddSubjectView()
            }
            .sheet(isPresented: $isCapturing) {
                AddEntryView(preselectedSubjectId: nil, preselectedTopicId: nil)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Working Knowledge")
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Theme.heroGradient)

            Text("Everything you figure out, held somewhere safe.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)

            HStack(spacing: 10) {
                statChip(value: store.subjects.count, label: "subjects")
                statChip(value: store.allEntries.count, label: "learnings")
                statChip(value: store.toolCount, label: "tools")
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
    }

    private func statChip(value: Int, label: String) -> some View {
        HStack(spacing: 5) {
            Text("\(value)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.cyan)
            Text(label)
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.surface, in: .capsule)
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "building.columns")
                .font(.system(size: 40))
                .foregroundStyle(Theme.dim)
            Text("Your palace is empty")
                .font(.headline)
                .foregroundStyle(Theme.body)
            Text("Add a subject you're learning to start\nfiling away what you figure out.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button {
                isAddingSubject = true
            } label: {
                Text("Add a Subject")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Theme.cyan, in: .capsule)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
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
        .disabled(store.subjects.isEmpty)
        .opacity(store.subjects.isEmpty ? 0.4 : 1)
    }
}
