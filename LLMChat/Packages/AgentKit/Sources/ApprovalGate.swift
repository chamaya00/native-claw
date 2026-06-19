import Foundation
import SwiftData
import Observation
import EventKit
import MemoryKit

/// The single chokepoint for every state-mutating action (Approval before mutation,
/// per the global guardrails). Tools never write directly — they emit a draft via
/// `ToolEvent`; the gate holds it as a pending proposal and performs the write only
/// when the user confirms. Memory writes, persona edits, and EventKit reminders all
/// route through here.
@Observable
@MainActor
public final class ApprovalGate {

    // Pending proposals — set by tools, cleared after the user acts.
    public var pendingMemoryNote: MemoryNoteDraft?
    public var pendingMemoryUpdate: MemoryUpdateDraft?
    public var pendingPersonaUpdate: PersonaUpdateDraft?
    public var pendingReminder: ReminderDraft?
    public var pendingCalendarEvent: CalendarEventDraft?

    private let container: ModelContainer
    private let eventStore = EKEventStore()

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Route a tool event into a pending proposal. Returns `true` if it was an
    /// approval request the gate now holds (the engine handles indicator events).
    @discardableResult
    public func submit(_ event: ToolEvent) -> Bool {
        switch event {
        case .pendingMemoryNote(let draft):
            pendingMemoryNote = draft
            return true
        case .pendingMemoryUpdate(let draft):
            pendingMemoryUpdate = draft
            return true
        case .pendingPersonaUpdate(let draft):
            pendingPersonaUpdate = draft
            return true
        case .pendingReminder(let draft):
            pendingReminder = draft
            return true
        case .pendingCalendarEvent(let draft):
            pendingCalendarEvent = draft
            return true
        case .toolStarted, .toolCompleted:
            return false
        }
    }

    public func clearAll() {
        pendingMemoryNote = nil
        pendingMemoryUpdate = nil
        pendingPersonaUpdate = nil
        pendingReminder = nil
        pendingCalendarEvent = nil
    }

    // MARK: - Memory note

    public func confirmMemoryNote() throws {
        guard let draft = pendingMemoryNote else { return }
        let context = ModelContext(container)
        let note = MemoryNote(
            title: draft.title,
            summary: draft.summary,
            sourceLabel: draft.sourceLabel,
            topics: draft.topics,
            importanceScore: draft.importanceScore,
            isUserApproved: true
        )
        context.insert(note)
        try context.save()
        pendingMemoryNote = nil
    }

    public func discardMemoryNote() { pendingMemoryNote = nil }

    // MARK: - Memory update

    public func confirmMemoryUpdate() throws {
        guard let draft = pendingMemoryUpdate else { return }
        let context = ModelContext(container)
        let id = draft.noteID
        let descriptor = FetchDescriptor<MemoryNote>(predicate: #Predicate { $0.id == id })
        guard let note = (try? context.fetch(descriptor))?.first else {
            pendingMemoryUpdate = nil
            return
        }
        if let t = draft.proposedTitle { note.title = t }
        if let s = draft.proposedSummary { note.summary = s }
        if let topics = draft.proposedTopics { note.topics = topics }
        if let score = draft.proposedImportanceScore { note.importanceScore = score }
        note.updatedAt = .now
        try context.save()
        pendingMemoryUpdate = nil
    }

    public func discardMemoryUpdate() { pendingMemoryUpdate = nil }

    // MARK: - Persona update

    public func confirmPersonaUpdate() throws {
        guard let draft = pendingPersonaUpdate else { return }
        let context = ModelContext(container)
        guard let persona = (try? context.fetch(FetchDescriptor<Persona>()))?.first else {
            pendingPersonaUpdate = nil
            return
        }
        if let v = draft.proposedVibe { persona.vibe = v }
        if let v = draft.proposedValues { persona.values = v }
        if let e = draft.proposedExpertiseAreas { persona.expertiseAreas = e }
        persona.updatedAt = .now
        try context.save()
        pendingPersonaUpdate = nil
    }

    public func discardPersonaUpdate() { pendingPersonaUpdate = nil }

    // MARK: - Reminder (EventKit)

    public enum ReminderError: LocalizedError {
        case accessDenied
        case noDefaultList
        case calendarAccessDenied
        case noDefaultCalendar
        case unparsableStart

        public var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Claw needs access to Reminders to create this. Allow it in Settings → Privacy → Reminders."
            case .noDefaultList:
                return "No default Reminders list is configured on this device."
            case .calendarAccessDenied:
                return "Claw needs access to Calendars to add this event. Allow it in Settings → Privacy → Calendars."
            case .noDefaultCalendar:
                return "No default calendar is configured on this device."
            case .unparsableStart:
                return "Couldn't understand the event's start time. Try rephrasing it (e.g. 'tomorrow at 2pm')."
            }
        }
    }

    public func confirmReminder() async throws {
        guard let draft = pendingReminder else { return }

        let granted = try await eventStore.requestFullAccessToReminders()
        guard granted else { throw ReminderError.accessDenied }
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            throw ReminderError.noDefaultList
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = draft.title
        reminder.notes = draft.notes
        reminder.calendar = calendar

        if let text = draft.dueDateText, let date = Self.detectDate(in: text) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: date
            )
            reminder.addAlarm(EKAlarm(absoluteDate: date))
        }

        try eventStore.save(reminder, commit: true)
        pendingReminder = nil
    }

    public func discardReminder() { pendingReminder = nil }

    // MARK: - Calendar event (EventKit)

    public func confirmCalendarEvent() async throws {
        guard let draft = pendingCalendarEvent else { return }

        let granted = try await eventStore.requestFullAccessToEvents()
        guard granted else { throw ReminderError.calendarAccessDenied }
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            throw ReminderError.noDefaultCalendar
        }
        guard let start = Self.detectDate(in: draft.startText) else {
            throw ReminderError.unparsableStart
        }

        let end = draft.endText.flatMap { Self.detectDate(in: $0) }
            ?? start.addingTimeInterval(3600)

        let event = EKEvent(eventStore: eventStore)
        event.title = draft.title
        event.location = draft.location
        event.notes = draft.notes
        event.startDate = start
        event.endDate = max(end, start.addingTimeInterval(300))
        event.calendar = calendar

        try eventStore.save(event, span: .thisEvent, commit: true)
        pendingCalendarEvent = nil
    }

    public func discardCalendarEvent() { pendingCalendarEvent = nil }

    /// Parse a natural-language due date ("tomorrow at 9am") into a concrete date.
    private static func detectDate(in text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return detector?.firstMatch(in: text, options: [], range: range)?.date
    }
}
