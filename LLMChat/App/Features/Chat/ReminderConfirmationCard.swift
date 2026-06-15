import SwiftUI
import MemoryKit

/// Confirmation card for the `createReminder` tool. The reminder is written to the
/// Reminders app only when the user taps **Add** — the approval-before-mutation rule
/// applied to a system-state change.
struct ReminderConfirmationCard: View {
    let draft: ReminderDraft
    let onConfirm: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add this reminder?", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                DiffRow(label: "Title", value: draft.title)
                if let notes = draft.notes { DiffRow(label: "Notes", value: notes) }
                if let due = draft.dueDateText { DiffRow(label: "Due", value: due) }
            }

            ConfirmActionButtons(
                discardTitle: "Discard",
                confirmTitle: "Add",
                confirmColor: .blue,
                onDiscard: onDiscard,
                onConfirm: onConfirm
            )
        }
        .cardStyle(border: Color.blue.opacity(0.3))
    }
}
