import SwiftUI
import SwiftData
import MemoryKit
import AgentKit

/// The in-app proactivity inbox (§Phase 5). The assistant proposes routines it noticed;
/// the user approves, edits, or dismisses them here. This is where "propose-then-approve"
/// is made real: nothing ever notifies until a routine is approved in this screen, and a
/// dismissal is a durable negative signal that suppresses similar future suggestions.
struct SuggestionInboxView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \SuggestedRoutine.createdAt, order: .reverse) private var routines: [SuggestedRoutine]

    @State private var editing: SuggestedRoutine?

    private var pending: [SuggestedRoutine] {
        routines.filter { $0.status == RoutineStatus.suggested.rawValue }
    }
    private var approved: [SuggestedRoutine] {
        routines.filter { $0.status == RoutineStatus.approved.rawValue }
    }

    var body: some View {
        Group {
            if pending.isEmpty && approved.isEmpty {
                emptyState
            } else {
                List {
                    if !pending.isEmpty { suggestedSection }
                    if !approved.isEmpty { approvedSection }
                    infoFooter
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Suggestions")
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $editing) { routine in
            RoutineEditSheet(routine: routine) { title, hint in
                updateRoutine(routine, title: title, scheduleHint: hint, context: modelContext)
            }
        }
    }

    // MARK: - Suggested (awaiting approval)

    private var suggestedSection: some View {
        Section {
            ForEach(pending) { routine in
                SuggestedRoutineRow(
                    routine: routine,
                    onApprove: { approve(routine) },
                    onDismiss: { dismissRoutine(routine, context: modelContext) },
                    onEdit: { editing = routine }
                )
            }
        } header: {
            Label("Suggested (\(pending.count))", systemImage: "tray.full")
        } footer: {
            Text("Claw noticed these patterns. Approve to turn one into a routine — only approved routines ever notify you.")
        }
    }

    // MARK: - Approved (active routines)

    private var approvedSection: some View {
        Section("Active routines") {
            ForEach(approved) { routine in
                VStack(alignment: .leading, spacing: 4) {
                    Text(routine.title).font(.subheadline.weight(.medium))
                    if let hint = routine.scheduleHint, !hint.isEmpty {
                        Label(hint, systemImage: "clock")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pauseRoutine(routine, context: modelContext)
                        ProactivityScheduler.scheduleIfNeeded(container: modelContext.container)
                    } label: { Label("Pause", systemImage: "pause") }
                    Button { editing = routine } label: { Label("Edit", systemImage: "pencil") }
                        .tint(.blue)
                }
            }
        }
    }

    private var infoFooter: some View {
        Section {
            EmptyView()
        } footer: {
            Label(
                "Briefings run in the background when iOS allows it (best-effort, not a fixed alarm) and are delivered as a notification.",
                systemImage: "bell.badge"
            )
            .font(.caption2)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No suggestions yet")
                .font(.title3.weight(.semibold))
            Text("As you chat, Claw notices patterns worth turning into routines — like a morning briefing — and proposes them here for you to approve.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Actions

    /// Approve, then request notification permission (progressive, value-framed) and arm the
    /// background schedule. Permission and scheduling are off the main path so the list
    /// updates immediately.
    private func approve(_ routine: SuggestedRoutine) {
        approveRoutine(routine, context: modelContext)
        let container = modelContext.container
        Task {
            await ProactivityScheduler.requestNotificationAuthorization()
            await MainActor.run { ProactivityScheduler.scheduleIfNeeded(container: container) }
        }
    }
}

// MARK: - Suggested routine row

private struct SuggestedRoutineRow: View {
    let routine: SuggestedRoutine
    let onApprove: () -> Void
    let onDismiss: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(routine.title).font(.subheadline.weight(.medium))
            Text(routine.rationale).font(.caption).foregroundStyle(.secondary)
            if let hint = routine.scheduleHint, !hint.isEmpty {
                Label(hint, systemImage: "clock")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: onApprove) {
                    Label("Approve", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button(action: onEdit) {
                    Label("Edit", systemImage: "pencil").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark").font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Edit sheet

private struct RoutineEditSheet: View {
    let routine: SuggestedRoutine
    let onSave: (_ title: String, _ scheduleHint: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var scheduleHint: String

    init(routine: SuggestedRoutine, onSave: @escaping (String, String?) -> Void) {
        self.routine = routine
        self.onSave = onSave
        _title = State(initialValue: routine.title)
        _scheduleHint = State(initialValue: routine.scheduleHint ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Routine name", text: $title)
                }
                Section("Schedule") {
                    TextField("e.g. weekdays 8am", text: $scheduleHint)
                } footer: {
                    Text("A natural-language hint. Briefings currently run around 8am when iOS allows background work.")
                }
            }
            .navigationTitle("Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = scheduleHint.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(title.trimmingCharacters(in: .whitespacesAndNewlines),
                               trimmed.isEmpty ? nil : trimmed)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
