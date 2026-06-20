import Foundation

// MARK: - Draft Types (non-persisted, pending user confirmation)
//
// Every mutating action proposes a draft that routes through AgentKit.ApprovalGate.
// Nothing here is written to disk until the user confirms.

public struct MemoryNoteDraft: Sendable, Identifiable {
    public let id = UUID()
    public var title: String
    public var summary: String
    public var topics: [String]
    public var importanceScore: Float
    public var sourceLabel: String?

    public init(
        title: String,
        summary: String,
        topics: [String],
        importanceScore: Float,
        sourceLabel: String?
    ) {
        self.title = title
        self.summary = summary
        self.topics = topics
        self.importanceScore = importanceScore
        self.sourceLabel = sourceLabel
    }
}

public struct MemoryUpdateDraft: Sendable, Identifiable {
    public let id = UUID()
    public var noteID: UUID
    public var originalTitle: String
    public var proposedTitle: String?
    public var proposedSummary: String?
    public var proposedTopics: [String]?
    public var proposedImportanceScore: Float?

    public init(
        noteID: UUID,
        originalTitle: String,
        proposedTitle: String?,
        proposedSummary: String?,
        proposedTopics: [String]?,
        proposedImportanceScore: Float?
    ) {
        self.noteID = noteID
        self.originalTitle = originalTitle
        self.proposedTitle = proposedTitle
        self.proposedSummary = proposedSummary
        self.proposedTopics = proposedTopics
        self.proposedImportanceScore = proposedImportanceScore
    }
}

public struct PersonaUpdateDraft: Sendable, Identifiable {
    public let id = UUID()
    public var proposedVibe: String?
    public var proposedValues: [String]?
    public var proposedExpertiseAreas: [String]?

    public init(
        proposedVibe: String?,
        proposedValues: [String]?,
        proposedExpertiseAreas: [String]?
    ) {
        self.proposedVibe = proposedVibe
        self.proposedValues = proposedValues
        self.proposedExpertiseAreas = proposedExpertiseAreas
    }
}

/// A proposed reminder. Written to EventKit only after approval (Phase 1's
/// first mutating *system* tool — proves the ApprovalGate → system-write path).
public struct ReminderDraft: Sendable, Identifiable {
    public let id = UUID()
    public var title: String
    public var notes: String?
    /// Natural-language due date as produced by the model (e.g. "tomorrow 9am").
    /// Parsed at confirmation time with `NSDataDetector`.
    public var dueDateText: String?

    public init(title: String, notes: String?, dueDateText: String?) {
        self.title = title
        self.notes = notes
        self.dueDateText = dueDateText
    }
}

/// A proposed calendar event (Phase 2). Written to EventKit only after approval —
/// the same gate the reminder tool uses, now for the richer "propose an event from
/// a screenshot" flow. Start/end are natural language parsed with `NSDataDetector`
/// at confirmation time so the model never has to format dates.
public struct CalendarEventDraft: Sendable, Identifiable {
    public let id = UUID()
    public var title: String
    public var location: String?
    public var notes: String?
    /// Natural-language start ("tomorrow 2pm", "next Friday 9am").
    public var startText: String
    /// Natural-language end, or empty to default to one hour after start.
    public var endText: String?

    public init(
        title: String,
        location: String?,
        notes: String?,
        startText: String,
        endText: String?
    ) {
        self.title = title
        self.location = location
        self.notes = notes
        self.startText = startText
        self.endText = endText
    }
}

// MARK: - In-memory Chat Message (for the UI thread)

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public var role: String          // "user" | "assistant"
    public var content: String
    public var toolCallsMade: [String]
    public var timestamp: Date
    public var isStreaming: Bool

    /// The model tier that produced an assistant turn, as a compact label + SF Symbol
    /// (e.g. "On-device" / "iphone"). Plain strings rather than the `ModelTier` type so
    /// this UI-thread struct stays free of an AgentKit dependency (§Phase 4 transparency).
    public var tierLabel: String?
    public var tierSystemImage: String?

    public init(
        id: UUID = .init(),
        role: String,
        content: String,
        toolCallsMade: [String] = [],
        isStreaming: Bool = false,
        tierLabel: String? = nil,
        tierSystemImage: String? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallsMade = toolCallsMade
        self.timestamp = .now
        self.isStreaming = isStreaming
        self.tierLabel = tierLabel
        self.tierSystemImage = tierSystemImage
    }
}

// MARK: - Tool Events (signalled from tools back to the agent / UI)

public enum ToolEvent: Sendable {
    case toolStarted(String)          // e.g. "Searching memory…"
    case toolCompleted
    case pendingMemoryNote(MemoryNoteDraft)
    case pendingMemoryUpdate(MemoryUpdateDraft)
    case pendingPersonaUpdate(PersonaUpdateDraft)
    case pendingReminder(ReminderDraft)
    case pendingCalendarEvent(CalendarEventDraft)
}
