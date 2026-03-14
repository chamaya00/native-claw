import SwiftUI

struct NameCaptureSheet: View {
    @Binding var isPresented: Bool
    let onConfirm: (String, LanguageDirection) -> Void

    @State private var name: String = ""
    @State private var direction: LanguageDirection = .vietnameseToEnglish
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Text(direction == .vietnameseToEnglish ? "🇻🇳" : "🇬🇧")
                    .font(.system(size: 56))
                    .animation(.tutorSpring, value: direction)
                Text(direction == .vietnameseToEnglish ? "Xin chào!" : "Hello!")
                    .font(.largeTitle.weight(.bold))
                Text(direction == .vietnameseToEnglish
                     ? "Bạn tên là gì?\nTôi sẽ gọi tên bạn trong suốt buổi học."
                     : "What's your name?\nI'll use it throughout our lesson.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Direction picker
            VStack(spacing: 8) {
                Text(direction == .vietnameseToEnglish ? "Tôi muốn học:" : "I want to learn:")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ForEach(LanguageDirection.allCases, id: \.rawValue) { dir in
                        Button {
                            withAnimation(.tutorSpring) { direction = dir }
                        } label: {
                            Text(dir.label)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(direction == dir ? Color.blue : Color(.secondarySystemBackground))
                                .foregroundStyle(direction == dir ? .white : .primary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule().stroke(direction == dir ? Color.blue : Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }

            VStack(spacing: 12) {
                TextField(
                    direction == .vietnameseToEnglish ? "Nhập tên của bạn..." : "Enter your name...",
                    text: $name
                )
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .focused($isFocused)
                    .onSubmit { confirmIfReady() }
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()

                Button(action: confirmIfReady) {
                    Text(direction == .vietnameseToEnglish ? "Bắt đầu học!" : "Start learning!")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(name.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.gray : Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .interactiveDismissDisabled()
        .onAppear { isFocused = true }
    }

    private func confirmIfReady() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Haptics.notification(.success)
        isPresented = false
        onConfirm(trimmed, direction)
    }
}
