import SwiftUI

/// Palace-scoped search across every learning entry.
/// Keyword mode uses the FTS5 index; semantic mode (real device + embedder)
/// searches by meaning.
struct SearchView: View {
    private enum Mode: String, CaseIterable {
        case keyword = "Keyword"
        case semantic = "Semantic"
    }

    @Environment(PalaceStore.self) private var store
    @Environment(ModelManager.self) private var models

    @State private var query: String = ""
    @State private var scopedSubjectName: String? = nil
    @State private var mode: Mode = .keyword
    @State private var semanticResults: [Entry] = []
    @State private var isSearchingSemantically: Bool = false

    private var results: [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [Entry]
        if trimmed.isEmpty {
            base = store.allEntries
        } else if mode == .semantic {
            base = semanticResults
        } else {
            let ftsHits = store.keywordSearch(trimmed)
            base = ftsHits.isEmpty ? substringMatches(trimmed) : ftsHits
        }
        guard let scope = scopedSubjectName else { return base }
        return base.filter { $0.subjectName == scope }
    }

    private func substringMatches(_ trimmed: String) -> [Entry] {
        store.allEntries.filter { entry in
            entry.question.localizedStandardContains(trimmed)
                || entry.learned.localizedStandardContains(trimmed)
                || entry.toolName.localizedStandardContains(trimmed)
                || entry.topicName.localizedStandardContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 14) {
                    searchField
                    if models.embedding.isReady {
                        modePicker
                    }
                    scopeChips

                    if isSearchingSemantically {
                        ProgressView()
                            .tint(Theme.cyan)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(results) { entry in
                                    NavigationLink(value: entry) {
                                        EntryRowView(entry: entry, showsBreadcrumb: true)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entryId: entry.id)
            }
            .task(id: "\(query)|\(mode.rawValue)") {
                await runSemanticSearchIfNeeded()
            }
        }
    }

    private func runSemanticSearchIfNeeded() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard mode == .semantic, !trimmed.isEmpty, models.embedding.isReady,
              let indexing = models.indexing else {
            semanticResults = []
            return
        }
        isSearchingSemantically = true
        defer { isSearchingSemantically = false }

        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }

        let vectors = indexing.loadEntryVectors()
        guard !vectors.isEmpty,
              let queryVector = try? await models.embedding.embedOne(trimmed, asQuery: true),
              !queryVector.isEmpty else {
            semanticResults = []
            return
        }
        let matches = VectorMath.topMatches(query: queryVector, among: vectors, limit: 30)
            .filter { $0.score > 0.1 }
        semanticResults = matches.compactMap { store.entry(id: $0.id) }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .semantic ? "sparkle.magnifyingglass" : "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(mode == .semantic ? Theme.violet : Theme.dim)

            TextField(
                mode == .semantic ? "Search by meaning…" : "Search your learnings…",
                text: $query
            )
            .font(.subheadline)
            .foregroundStyle(Theme.ice)
            .autocorrectionDisabled()

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(query.isEmpty ? Theme.border : Theme.cyan.opacity(0.4), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(Mode.allCases, id: \.self) { option in
                Button {
                    mode = option
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: option == .semantic ? "brain" : "textformat")
                            .font(.system(size: 10, weight: .semibold))
                        Text(option.rawValue)
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(mode == option ? Theme.bg : Theme.muted)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        mode == option
                            ? AnyShapeStyle(option == .semantic ? Theme.violet : Theme.cyan)
                            : AnyShapeStyle(Theme.surface),
                        in: .capsule
                    )
                    .overlay(
                        Capsule().stroke(mode == option ? Color.clear : Theme.border, lineWidth: 1)
                    )
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var scopeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                scopeChip(label: "All", isSelected: scopedSubjectName == nil) {
                    scopedSubjectName = nil
                }
                ForEach(store.subjects) { subject in
                    scopeChip(label: subject.name, isSelected: scopedSubjectName == subject.name) {
                        scopedSubjectName = subject.name
                    }
                }
            }
        }
        .contentMargins(.horizontal, 16)
    }

    private func scopeChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Theme.bg : Theme.muted)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(isSelected ? AnyShapeStyle(Theme.cyan) : AnyShapeStyle(Theme.surface), in: .capsule)
                .overlay(
                    Capsule().stroke(isSelected ? Color.clear : Theme.border, lineWidth: 1)
                )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Theme.dim)
            Text(query.isEmpty ? "Nothing filed yet" : "No matches")
                .font(.headline)
                .foregroundStyle(Theme.body)
            Text(query.isEmpty
                 ? "Learnings you capture will be searchable here."
                 : "Try a different word — search covers questions,\nanswers, topics, tools, and attachment text.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
