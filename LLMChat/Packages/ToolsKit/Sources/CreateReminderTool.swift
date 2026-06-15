import Foundation
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

/// Phase 1's first mutating *system* tool. It never writes directly — it proposes
/// a `ReminderDraft` that routes through `AgentKit.ApprovalGate`, which performs the
/// EventKit write only after explicit user confirmation. This makes "approve before
/// mutation" structural for system-state changes, not just memory writes.
struct CreateReminderTool: Tool {
    static let toolName = "createReminder"
    let name = CreateReminderTool.toolName
    let description = "Propose creating a reminder in the user's Reminders app. The user must confirm before it is created."

    @Generable
    struct Arguments {
        @Guide(description: "The reminder title — a short, actionable phrase")
        var title: String

        @Guide(description: "Optional extra notes/details, or empty string if none")
        var notes: String

        @Guide(description: "Optional due date in natural language (e.g. 'tomorrow at 9am', 'next Monday'), or empty string if none")
        var due: String
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        let draft = ReminderDraft(
            title: arguments.title,
            notes: arguments.notes.isEmpty ? nil : arguments.notes,
            dueDateText: arguments.due.isEmpty ? nil : arguments.due
        )
        await onEvent(.pendingReminder(draft))

        var lines = ["Reminder proposal ready for confirmation.", "Title: \(draft.title)"]
        if let due = draft.dueDateText { lines.append("Due: \(due)") }
        lines.append("A confirmation card will appear in the chat. The reminder is created only if the user approves.")
        return lines.joined(separator: "\n")
    }
}

#endif
