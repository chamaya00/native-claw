import SwiftUI
import MemoryKit

// MARK: - Memory Note Confirmation Card

struct MemoryNoteConfirmationCard: View {
    let draft: MemoryNoteDraft
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Save to memory?", systemImage: "brain")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(String(format: "%.0f%%", draft.importanceScore * 100))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5), in: Capsule())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(draft.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)

                Text(draft.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)

                if !draft.topics.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(draft.topics, id: \.self) { topic in
                            Text(topic)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.systemGray5), in: Capsule())
                        }
                    }
                }

                if let source = draft.sourceLabel {
                    Text(source)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            ConfirmActionButtons(
                discardTitle: "Discard",
                confirmTitle: "Save",
                confirmColor: .accentColor,
                onDiscard: onDiscard,
                onConfirm: onSave
            )
        }
        .cardStyle(border: Color.accentColor.opacity(0.25))
    }
}

// MARK: - Memory Update Confirmation Card

struct MemoryUpdateConfirmationCard: View {
    let draft: MemoryUpdateDraft
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Update memory?", systemImage: "brain.head.profile")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Note: \(draft.originalTitle)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let t = draft.proposedTitle { DiffRow(label: "Title", value: t) }
                if let s = draft.proposedSummary { DiffRow(label: "Summary", value: s) }
                if let topics = draft.proposedTopics { DiffRow(label: "Topics", value: topics.joined(separator: ", ")) }
                if let score = draft.proposedImportanceScore {
                    DiffRow(label: "Importance", value: String(format: "%.0f%%", score * 100))
                }
            }

            ConfirmActionButtons(
                discardTitle: "Discard",
                confirmTitle: "Save",
                confirmColor: .orange,
                onDiscard: onDiscard,
                onConfirm: onSave
            )
        }
        .cardStyle(border: Color.orange.opacity(0.3))
    }
}

// MARK: - Persona Update Confirmation Card

struct PersonaUpdateConfirmationCard: View {
    let draft: PersonaUpdateDraft
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Update persona?", systemImage: "person.crop.circle.badge.plus")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                if let v = draft.proposedVibe { DiffRow(label: "Vibe", value: v) }
                if let v = draft.proposedValues { DiffRow(label: "Values", value: v.joined(separator: ", ")) }
                if let e = draft.proposedExpertiseAreas { DiffRow(label: "Expertise", value: e.joined(separator: ", ")) }
            }

            ConfirmActionButtons(
                discardTitle: "Discard",
                confirmTitle: "Update",
                confirmColor: .purple,
                onDiscard: onDiscard,
                onConfirm: onSave
            )
        }
        .cardStyle(border: Color.purple.opacity(0.3))
    }
}

// MARK: - Calendar Event Confirmation Card

struct CalendarEventConfirmationCard: View {
    let draft: CalendarEventDraft
    let onConfirm: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Add this event?", systemImage: "calendar.badge.plus")
                .font(.subheadline.weight(.semibold))

            VStack(alignment: .leading, spacing: 4) {
                DiffRow(label: "Title", value: draft.title)
                DiffRow(label: "Start", value: draft.startText)
                if let end = draft.endText { DiffRow(label: "End", value: end) }
                if let location = draft.location { DiffRow(label: "Where", value: location) }
                if let notes = draft.notes { DiffRow(label: "Notes", value: notes) }
            }

            ConfirmActionButtons(
                discardTitle: "Discard",
                confirmTitle: "Add",
                confirmColor: .green,
                onDiscard: onDiscard,
                onConfirm: onConfirm
            )
        }
        .cardStyle(border: Color.green.opacity(0.3))
    }
}

// MARK: - Shared building blocks

struct DiffRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
    }
}

struct ConfirmActionButtons: View {
    let discardTitle: String
    let confirmTitle: String
    let confirmColor: Color
    let onDiscard: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onDiscard) {
                Text(discardTitle)
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.primary)
            }
            Button(action: onConfirm) {
                Text(confirmTitle)
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(confirmColor, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
        }
    }
}

extension View {
    func cardStyle(border: Color) -> some View {
        self
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }
}
