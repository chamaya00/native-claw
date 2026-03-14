import SwiftUI

struct ExerciseOverlay: View {
    let exercise: Exercise
    let exerciseIndex: Int
    let totalExercises: Int
    let progress: Double
    var direction: LanguageDirection = .vietnameseToEnglish
    let onAnswer: (String) -> Void

    @State private var selectedAnswer: String = ""
    @State private var typedAnswer: String = ""
    @State private var showingResult: Bool = false
    @State private var lastAnswerCorrect: Bool = false
    @State private var shake: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 4)
                    Capsule()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * progress, height: 4)
                        .animation(.tutorSpring, value: progress)
                }
            }
            .frame(height: 4)
            .padding(.bottom, 16)

            // Exercise counter
            Text(direction == .vietnameseToEnglish
                 ? "Bai \(exerciseIndex + 1)/\(totalExercises)"
                 : "Q. \(exerciseIndex + 1)/\(totalExercises)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            // Exercise content (morphs between exercises)
            exerciseContent
                .id(exercise.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
                .animation(.exerciseTransition, value: exercise.id)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 8)
        .offset(x: shake ? -8 : 0)
        .onChange(of: exercise.id) { _, _ in
            selectedAnswer = ""
            typedAnswer = ""
            showingResult = false
        }
    }

    // MARK: - Exercise Content

    @ViewBuilder
    private var exerciseContent: some View {
        switch exercise.type {
        case .multipleChoice:
            multipleChoiceView
        case .fillBlank, .translate:
            translateView
        }
    }

    // MARK: - Multiple Choice

    private var multipleChoiceView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exercise.prompt)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(exercise.options, id: \.self) { option in
                    OptionButton(
                        label: option,
                        state: optionState(for: option),
                        isDisabled: showingResult
                    ) {
                        submitMultipleChoice(option)
                    }
                }
            }
        }
    }

    private func optionState(for option: String) -> OptionButton.State {
        guard showingResult else {
            return selectedAnswer == option ? .selected : .normal
        }
        if option == exercise.correctAnswer { return .correct }
        if option == selectedAnswer && !lastAnswerCorrect { return .wrong }
        return .normal
    }

    private func submitMultipleChoice(_ answer: String) {
        guard !showingResult else { return }
        selectedAnswer = answer
        let isCorrect = answer == exercise.correctAnswer
        lastAnswerCorrect = isCorrect
        showingResult = true

        if !isCorrect {
            triggerShake()
        }

        Task {
            try? await Task.sleep(nanoseconds: isCorrect ? 600_000_000 : 800_000_000)
            onAnswer(answer)
        }
    }

    // MARK: - Translate / Fill Blank

    private var translateView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(exercise.prompt)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            TextField(direction == .vietnameseToEnglish ? "Nhap cau tra loi..." : "Type your answer...", text: $typedAnswer)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .disabled(showingResult)
                .overlay(alignment: .trailing) {
                    if showingResult {
                        Image(systemName: lastAnswerCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(lastAnswerCorrect ? .green : .red)
                            .padding(.trailing, 10)
                    }
                }

            if showingResult && !lastAnswerCorrect {
                HStack(spacing: 4) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.orange)
                    Text(direction == .vietnameseToEnglish
                         ? "Dap an: \(exercise.correctAnswer)"
                         : "Answer: \(exercise.correctAnswer)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                submitTyped()
            } label: {
                Text(showingResult
                     ? (direction == .vietnameseToEnglish ? "Tiep tuc..." : "Continue...")
                     : (direction == .vietnameseToEnglish ? "Kiem tra" : "Check"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(typedAnswer.isEmpty && !showingResult ? Color.gray : Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(typedAnswer.isEmpty && !showingResult)
        }
    }

    private func submitTyped() {
        guard !showingResult else { return }
        let normalized = typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correct = exercise.correctAnswer.lowercased()
        let isCorrect = normalized == correct
        lastAnswerCorrect = isCorrect
        showingResult = true

        if !isCorrect {
            triggerShake()
        }

        Task {
            try? await Task.sleep(nanoseconds: isCorrect ? 600_000_000 : 800_000_000)
            onAnswer(typedAnswer)
        }
    }

    // MARK: - Shake Effect

    private func triggerShake() {
        withAnimation(.tutorSpring) { shake = true }
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.tutorSpring) { shake = false }
        }
    }
}

// MARK: - Option Button

private struct OptionButton: View {
    enum State { case normal, selected, correct, wrong }

    let label: String
    let state: State
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(foregroundColor)
                Spacer()
                if state == .correct {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if state == .wrong {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(borderColor, lineWidth: 1.5)
            )
        }
        .disabled(isDisabled)
        .animation(.tutorSpring, value: state)
    }

    private var backgroundColor: Color {
        switch state {
        case .normal: return Color(.secondarySystemBackground)
        case .selected: return Color.blue.opacity(0.1)
        case .correct: return Color.green.opacity(0.1)
        case .wrong: return Color.red.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        switch state {
        case .normal: return .primary
        case .selected: return .blue
        case .correct: return .green
        case .wrong: return .red
        }
    }

    private var borderColor: Color {
        switch state {
        case .normal: return Color(.systemGray4)
        case .selected: return .blue.opacity(0.5)
        case .correct: return .green.opacity(0.5)
        case .wrong: return .red.opacity(0.5)
        }
    }
}
