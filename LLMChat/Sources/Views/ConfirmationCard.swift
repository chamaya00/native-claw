import SwiftUI

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

            HStack(spacing: 8) {
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.primary)
                }

                Button(action: onSave) {
                    Text("Save")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 16)
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

                if let t = draft.proposedTitle {
                    diffRow(label: "Title", value: t)
                }
                if let s = draft.proposedSummary {
                    diffRow(label: "Summary", value: s)
                }
                if let topics = draft.proposedTopics {
                    diffRow(label: "Topics", value: topics.joined(separator: ", "))
                }
                if let score = draft.proposedImportanceScore {
                    diffRow(label: "Importance", value: String(format: "%.0f%%", score * 100))
                }
            }

            actionButtons
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func diffRow(label: String, value: String) -> some View {
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

    private var actionButtons: some View {
        HStack(spacing: 8) {
            Button(action: onDiscard) {
                Text("Discard")
                    .font(.footnote.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.primary)
            }
            Button(action: onSave) {
                Text("Save")
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.orange, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
        }
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
                if let v = draft.proposedVibe {
                    diffRow(label: "Vibe", value: v)
                }
                if let v = draft.proposedValues {
                    diffRow(label: "Values", value: v.joined(separator: ", "))
                }
                if let e = draft.proposedExpertiseAreas {
                    diffRow(label: "Expertise", value: e.joined(separator: ", "))
                }
            }

            HStack(spacing: 8) {
                Button(action: onDiscard) {
                    Text("Discard")
                        .font(.footnote.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.primary)
                }
                Button(action: onSave) {
                    Text("Update")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.purple, in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }

    private func diffRow(label: String, value: String) -> some View {
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
