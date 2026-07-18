import SwiftUI

/// Sheet for creating a new subject (wing).
struct AddSubjectView: View {
    @Environment(PalaceStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var symbolName: String = "cpu"
    @State private var accent: SubjectColor = .cyan

    private let symbols: [String] = [
        "cpu", "book.fill", "flask.conical.fill", "leaf.fill",
        "paintbrush.fill", "hammer.fill", "music.note", "camera.fill",
        "globe.americas.fill", "function", "atom", "heart.fill",
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SUBJECT NAME")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.dim)
                        TextField("e.g. Microcontrollers", text: $name)
                            .font(.body)
                            .foregroundStyle(Theme.ice)
                            .padding(14)
                            .background(Theme.surface, in: .rect(cornerRadius: 12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("SYMBOL")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.dim)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 10) {
                            ForEach(symbols, id: \.self) { symbol in
                                Button {
                                    symbolName = symbol
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 17))
                                        .foregroundStyle(symbolName == symbol ? accent.color : Theme.muted)
                                        .frame(width: 46, height: 46)
                                        .background(
                                            symbolName == symbol ? accent.color.opacity(0.15) : Theme.surface,
                                            in: .rect(cornerRadius: 10)
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(
                                                    symbolName == symbol ? accent.color.opacity(0.5) : Theme.border,
                                                    lineWidth: 1
                                                )
                                        )
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ACCENT")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Theme.dim)
                        HStack(spacing: 12) {
                            ForEach(SubjectColor.allCases) { option in
                                Button {
                                    accent = option
                                } label: {
                                    Circle()
                                        .fill(option.color)
                                        .frame(width: 34, height: 34)
                                        .overlay(
                                            Circle()
                                                .stroke(Theme.ice, lineWidth: accent == option ? 2 : 0)
                                                .padding(2)
                                        )
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .presentationBackground(Theme.bg)
            .navigationTitle("New Subject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        store.addSubject(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            symbolName: symbolName,
            colorRaw: accent.rawValue
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
