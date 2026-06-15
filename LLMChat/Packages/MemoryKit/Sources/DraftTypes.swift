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

// MARK: - In-memory Chat Message (for the UI thread)

public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public var role: String          // "user" | "assistant"
    public var content: String
    public var toolCallsMade: [String]
    public var timestamp: Date
    public var isStreaming: Bool

    public init(
        id: UUID = .init(),
        role: String,
        content: String,
        toolCallsMade: [String] = [],
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallsMade = toolCallsMade
        self.timestamp = .now
        self.isStreaming = isStreaming
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
}
