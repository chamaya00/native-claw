import SwiftUI
import AgentKit

/// The A/B preference picker, shown occasionally under a chat turn (§Phase 5). Two variants
/// of the answer that differ on one style axis; the user taps the one they prefer and the
/// winning style folds into the persona. Always skippable, fully on-device.
struct PreferenceChoiceCard: View {
    let choice: PreferenceChoice
    let onPick: (_ pickedA: Bool) -> Void
    let onSkip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Which do you prefer?", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Skip", action: onSkip)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("Tap the reply you like better — I'll write more like it.")
                .font(.caption)
                .foregroundStyle(.secondary)

            variantButton(text: choice.variantA, label: "A", pickedA: true)
            variantButton(text: choice.variantB, label: "B", pickedA: false)
        }
        .cardStyle(border: Color.accentColor.opacity(0.25))
    }

    private func variantButton(text: String, label: String, pickedA: Bool) -> some View {
        Button { onPick(pickedA) } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(Color.accentColor, in: Circle())
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
