import Foundation
import EventKit
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

// MARK: - readCalendar (read — no approval)

/// Reads upcoming events from the user's calendars. Reads never mutate, so they
/// don't route through the ApprovalGate (per §B: reads vs. writes correctly classified).
struct ReadCalendarTool: Tool {
    static let toolName = "readCalendar"
    let name = ReadCalendarTool.toolName
    let description = "Read the user's calendar events within a day range. Use for questions like 'what's on my calendar tomorrow?'."

    @Generable
    struct Arguments {
        @Guide(description: "Days from today to start the range (0 = today, 1 = tomorrow)", .range(0...60))
        var startDayOffset: Int

        @Guide(description: "Days from today to end the range, inclusive. Use the same value as start for a single day.", .range(0...60))
        var endDayOffset: Int
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Reading calendar…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let store = EKEventStore()
        let granted = try await store.requestFullAccessToEvents()
        guard granted else {
            return "Calendar access hasn't been granted. The user can enable it in Settings → Privacy → Calendars."
        }

        let calendar = Calendar.current
        let lower = min(arguments.startDayOffset, arguments.endDayOffset)
        let upper = max(arguments.startDayOffset, arguments.endDayOffset)
        let startDay = calendar.startOfDay(for: calendar.date(byAdding: .day, value: lower, to: .now) ?? .now)
        let endBase = calendar.date(byAdding: .day, value: upper, to: .now) ?? .now
        let endDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endBase) ?? endBase

        let predicate = store.predicateForEvents(withStart: startDay, end: endDay, calendars: nil)
        let events = store.events(matching: predicate).sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            return "No events found between \(startDay.formatted(date: .abbreviated, time: .omitted)) and \(endDay.formatted(date: .abbreviated, time: .omitted))."
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d, h:mm a"

        let lines = events.prefix(20).map { event -> String in
            let when = event.isAllDay
                ? "\(event.startDate.formatted(date: .abbreviated, time: .omitted)) (all day)"
                : formatter.string(from: event.startDate)
            let place = (event.location?.isEmpty == false) ? " @ \(event.location!)" : ""
            return "- \(event.title ?? "Untitled"): \(when)\(place)"
        }
        return "Calendar events:\n" + lines.joined(separator: "\n")
    }
}

// MARK: - createCalendarEvent (write — approval-gated)

/// Proposes a calendar event. Like `createReminder`, it never writes directly — it emits
/// a `CalendarEventDraft` that routes through `AgentKit.ApprovalGate`, which performs the
/// EventKit write only after explicit confirmation. This is the "add this event from the
/// screenshot" Phase 2 acceptance path.
struct CreateCalendarEventTool: Tool {
    static let toolName = "createCalendarEvent"
    let name = CreateCalendarEventTool.toolName
    let description = "Propose creating a calendar event. The user must confirm before it is added to their calendar."

    @Generable
    struct Arguments {
        @Guide(description: "The event title — a short, descriptive phrase")
        var title: String

        @Guide(description: "Start time in natural language (e.g. 'tomorrow at 2pm', 'next Friday 9am')")
        var start: String

        @Guide(description: "End time in natural language, or empty string to default to one hour")
        var end: String

        @Guide(description: "Optional location, or empty string if none")
        var location: String

        @Guide(description: "Optional notes/details, or empty string if none")
        var notes: String
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        let draft = CalendarEventDraft(
            title: arguments.title,
            location: arguments.location.isEmpty ? nil : arguments.location,
            notes: arguments.notes.isEmpty ? nil : arguments.notes,
            startText: arguments.start,
            endText: arguments.end.isEmpty ? nil : arguments.end
        )
        await onEvent(.pendingCalendarEvent(draft))

        var lines = ["Calendar event proposal ready for confirmation.", "Title: \(draft.title)", "Start: \(draft.startText)"]
        if let location = draft.location { lines.append("Location: \(location)") }
        lines.append("A confirmation card will appear in the chat. The event is created only if the user approves.")
        return lines.joined(separator: "\n")
    }
}

#endif
