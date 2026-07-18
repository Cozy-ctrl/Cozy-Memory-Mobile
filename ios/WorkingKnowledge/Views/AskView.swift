import SwiftUI

/// Ask Palace — question in, grounded answer out. Streams tokens from the
/// on-device pipeline and cites the exact learnings it drew from.
struct AskView: View {
    @Environment(PalaceStore.self) private var store
    @Environment(ModelManager.self) private var models
    @Environment(AskEngine.self) private var engine

    @State private var question: String = ""
    @State private var isShowingModelManager: Bool = false
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        askField
                        statusBanner

                        if engine.stage != .idle {
                            answerSection
                        }

                        if !engine.isWorking && !store.askHistory.isEmpty {
                            historySection
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 32)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Ask")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingModelManager = true
                    } label: {
                        Image(systemName: "cpu")
                    }
                }
            }
            .sheet(isPresented: $isShowingModelManager) {
                ModelManagerView()
            }
            .navigationDestination(for: Entry.self) { entry in
                EntryDetailView(entryId: entry.id)
            }
        }
    }

    // MARK: - Header & input

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Ask your palace")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(Theme.heroGradient)
            Text("Answers come only from what you've captured — private, on-device, cited.")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .padding(.top, 10)
    }

    private var askField: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.violet)

            TextField("e.g. Which black wire is ground?", text: $question, axis: .vertical)
                .lineLimit(1...3)
                .font(.subheadline)
                .foregroundStyle(Theme.ice)
                .focused($isFieldFocused)
                .onSubmit(submit)

            if engine.isWorking {
                Button {
                    engine.cancel()
                } label: {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.hot)
                }
            } else {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(
                            question.trimmingCharacters(in: .whitespaces).isEmpty
                                ? AnyShapeStyle(Theme.dim)
                                : AnyShapeStyle(Theme.cyanVioletGradient)
                        )
                }
                .disabled(question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(Theme.surface, in: .rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isFieldFocused ? Theme.violet.opacity(0.5) : Theme.border, lineWidth: 1)
        )
    }

    private func submit() {
        let text = question
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isFieldFocused = false
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        Task {
            await engine.ask(text)
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusBanner: some View {
        if !AIAvailability.isOnDeviceSupported {
            banner(
                symbol: "iphone.gen3",
                tint: Theme.warn,
                title: "Real iPhone required for AI answers",
                message: AIAvailability.simulatorNotice
            )
        } else if !ModelCatalog.synthesis.isDownloaded && !models.synthesis.isReady {
            Button {
                isShowingModelManager = true
            } label: {
                banner(
                    symbol: "arrow.down.circle",
                    tint: Theme.cyan,
                    title: "Download the on-device models",
                    message: "Get the answer model (~1 GB) and friends in the Model Manager. Until then, Ask falls back to Apple Intelligence when available."
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func banner(symbol: String, tint: Color, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.ice)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Answer

    private var answerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !engine.currentQuestion.isEmpty {
                Text(engine.currentQuestion)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Theme.cyan, in: .rect(cornerRadius: 14))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            stageIndicator

            if !engine.answer.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(engine.answer)
                        .font(.callout)
                        .foregroundStyle(Theme.body)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)

                    if !engine.engineLabel.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield")
                                .font(.system(size: 9))
                            Text(engine.engineLabel)
                                .font(.caption2.weight(.medium))
                        }
                        .foregroundStyle(Theme.dim)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Theme.surface, in: .rect(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Theme.violet.opacity(0.3), lineWidth: 1)
                )
            }

            if case .failed(let message) = engine.stage {
                banner(
                    symbol: "exclamationmark.triangle",
                    tint: Theme.hot,
                    title: "Couldn't answer",
                    message: message
                )
            }

            if !engine.sources.isEmpty {
                sourcesSection
            }
        }
    }

    @ViewBuilder
    private var stageIndicator: some View {
        if engine.isWorking {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.cyan)
                    .scaleEffect(0.8)
                Text(stageLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.opacity)
            }
            .padding(.vertical, 2)
        }
    }

    private var stageLabel: String {
        switch engine.stage {
        case .retrieving: return "Searching your palace (keywords + meaning)…"
        case .reranking: return "Reranking the best matches…"
        case .generating: return "Writing the answer from your learnings…"
        default: return ""
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SOURCES")
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.dim)
                .tracking(0.8)

            VStack(spacing: 8) {
                ForEach(Array(engine.sources.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink(value: entry) {
                        HStack(alignment: .top, spacing: 10) {
                            Text("[\(index + 1)]")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.violet)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.question)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.ice)
                                    .lineLimit(2)
                                Text("\(entry.subjectName) › \(entry.topicName) · \(entry.toolName)")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.dim)
                        }
                        .padding(11)
                        .background(Theme.surface, in: .rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - History

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RECENT QUESTIONS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.dim)
                    .tracking(0.8)
                Spacer()
                Button("Clear") {
                    store.clearAskHistory()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.dim)
            }

            VStack(spacing: 8) {
                ForEach(store.askHistory.prefix(8)) { exchange in
                    Button {
                        question = exchange.question
                        submit()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.dim)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(exchange.question)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(Theme.body)
                                    .lineLimit(1)
                                Text(exchange.answer)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(11)
                        .background(Theme.surface.opacity(0.6), in: .rect(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
