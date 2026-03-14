import SwiftUI

struct FeedbackCard: View {
    let feedback: RoundFeedback
    var direction: LanguageDirection = .vietnameseToEnglish
    @State private var badgeScale: CGFloat = 0.5
    @State private var progressWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Score header
            HStack(spacing: 12) {
                scoreBadge
                VStack(alignment: .leading, spacing: 2) {
                    Text(feedback.commentVi)
                        .font(.subheadline.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemGray5)).frame(height: 6)
                    Capsule()
                        .fill(scoreColor)
                        .frame(width: progressWidth * geo.size.width, height: 6)
                        .animation(.tutorSpring.delay(0.3), value: progressWidth)
                }
            }
            .frame(height: 6)

            // Corrections
            if !feedback.corrections.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(direction == .vietnameseToEnglish ? "Xem lai:" : "Review:")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(Array(feedback.corrections.enumerated()), id: \.offset) { _, correction in
                        CorrectionRow(correction: correction, direction: direction)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onAppear {
            withAnimation(.tutorSpring.delay(0.1)) {
                badgeScale = 1
            }
            progressWidth = Double(feedback.score) / Double(max(feedback.total, 1))
        }
    }

    private var scoreBadge: some View {
        ZStack {
            Circle()
                .fill(scoreColor.opacity(0.15))
                .frame(width: 52, height: 52)
            VStack(spacing: 1) {
                Text("\(feedback.score)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(scoreColor)
                Text("/\(feedback.total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .scaleEffect(badgeScale)
    }

    private var scoreColor: Color {
        let ratio = Double(feedback.score) / Double(max(feedback.total, 1))
        if ratio >= 0.8 { return .green }
        if ratio >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Correction Row

private struct CorrectionRow: View {
    let correction: RoundFeedback.Correction
    var direction: LanguageDirection = .vietnameseToEnglish

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(correction.prompt)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(correction.studentAnswer.isEmpty
                     ? (direction == .vietnameseToEnglish ? "(khong tra loi)" : "(no answer)")
                     : correction.studentAnswer)
                    .strikethrough()
                    .foregroundStyle(.red)
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(correction.correctedAnswer)
                    .foregroundStyle(.green)
            }
            .font(.subheadline)
            Text(correction.explanation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
