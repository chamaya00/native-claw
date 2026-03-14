import SwiftUI

struct WordGridSheet: View {
    let words: [WordEntry]
    @Binding var selectedWords: [WordEntry]
    var direction: LanguageDirection = .vietnameseToEnglish
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(words) { word in
                            WordCell(
                                word: word,
                                direction: direction,
                                isSelected: selectedWords.contains(where: { $0.id == word.id })
                            ) {
                                toggleSelection(word)
                            }
                        }
                    }
                    .padding()
                }

                Divider()

                confirmBar
            }
            .navigationTitle(direction == .vietnameseToEnglish ? "Chon tu vung" : "Choose words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(direction == .vietnameseToEnglish ? "Huy" : "Cancel") { onDismiss() }
                }
            }
        }
    }

    private var confirmBar: some View {
        VStack(spacing: 4) {
            Text(selectionLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: onConfirm) {
                Text(direction == .vietnameseToEnglish
                     ? "Hoc \(selectedWords.count) tu nay"
                     : "Learn \(selectedWords.count) words")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(selectedWords.isEmpty ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(selectedWords.isEmpty)
            .padding()
        }
        .background(Color(.systemBackground))
    }

    private var selectionLabel: String {
        if direction == .vietnameseToEnglish {
            switch selectedWords.count {
            case 0: return "Chon 1\u{2013}3 tu"
            case 1: return "Da chon 1 tu"
            default: return "Da chon \(selectedWords.count) tu"
            }
        } else {
            switch selectedWords.count {
            case 0: return "Select 1\u{2013}3 words"
            case 1: return "1 word selected"
            default: return "\(selectedWords.count) words selected"
            }
        }
    }

    private func toggleSelection(_ word: WordEntry) {
        if let idx = selectedWords.firstIndex(where: { $0.id == word.id }) {
            selectedWords.remove(at: idx)
            Haptics.impact(.light)
        } else if selectedWords.count < 3 {
            selectedWords.append(word)
            Haptics.impact(.medium)
        } else {
            Haptics.notification(.warning)
        }
    }
}

// MARK: - Word Cell

private struct WordCell: View {
    let word: WordEntry
    var direction: LanguageDirection = .vietnameseToEnglish
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(word.nativeWord(for: direction))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.white)
                            .font(.footnote)
                    }
                }

                Text(word.targetWord(for: direction))
                    .font(.footnote)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)

                Text(direction == .vietnameseToEnglish
                     ? "\(word.partOfSpeech) \u{00B7} \(word.partOfSpeech.partOfSpeechVietnamese)"
                     : word.partOfSpeech)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.65) : Color(.tertiaryLabel))
                    .italic()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .animation(.tutorSpring, value: isSelected)
    }
}

private extension String {
    var partOfSpeechVietnamese: String {
        switch self.lowercased() {
        case "noun":         return "danh tu"
        case "verb":         return "dong tu"
        case "adjective":    return "tinh tu"
        case "adverb":       return "trang tu"
        case "pronoun":      return "dai tu"
        case "preposition":  return "gioi tu"
        case "conjunction":  return "lien tu"
        case "interjection": return "than tu"
        case "phrase":       return "cum tu"
        default:             return self
        }
    }
}
