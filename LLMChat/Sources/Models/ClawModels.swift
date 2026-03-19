import Foundation
import SwiftData

// MARK: - SwiftData Models

@Model
final class Persona {
    var name: String
    var purpose: String
    var tone: String
    var values: [String]
    var expertiseAreas: [String]
    var updatedAt: Date

    init(
        name: String = "Claw",
        purpose: String,
        tone: String,
        values: [String],
        expertiseAreas: [String]
    ) {
        self.name = name
        self.purpose = purpose
        self.tone = tone
        self.values = values
        self.expertiseAreas = expertiseAreas
        self.updatedAt = .now
    }
}

@Model
final class MemoryNote {
    var id: UUID
    var title: String
    var summary: String
    var sourceLabel: String?
    var topics: [String]
    var importanceScore: Float
    var isUserApproved: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = .init(),
        title: String,
        summary: String,
        sourceLabel: String? = nil,
        topics: [String] = [],
        importanceScore: Float = 0.5,
        isUserApproved: Bool = false
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sourceLabel = sourceLabel
        self.topics = topics
        self.importanceScore = importanceScore
        self.isUserApproved = isUserApproved
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
final class TopicProfile {
    var id: UUID
    var topicName: String
    var interestScore: Float
    var familiarityScore: Float
    var preferredDepth: String  // "surface" | "working" | "deep"
    var lastUpdated: Date

    init(
        id: UUID = .init(),
        topicName: String,
        interestScore: Float = 0.5,
        familiarityScore: Float = 0.5,
        preferredDepth: String = "working"
    ) {
        self.id = id
        self.topicName = topicName
        self.interestScore = interestScore
        self.familiarityScore = familiarityScore
        self.preferredDepth = preferredDepth
        self.lastUpdated = .now
    }
}

@Model
final class ImportedFile {
    var id: UUID
    var filename: String
    var contentPreview: String  // first ~500 chars
    var fullText: String
    var importedAt: Date
    var lastAccessedAt: Date?

    init(
        id: UUID = .init(),
        filename: String,
        contentPreview: String,
        fullText: String
    ) {
        self.id = id
        self.filename = filename
        self.contentPreview = contentPreview
        self.fullText = fullText
        self.importedAt = .now
        self.lastAccessedAt = nil
    }
}

@Model
final class Conversation {
    var id: UUID
    var startedAt: Date
    @Relationship(deleteRule: .cascade) var messages: [Message]
    var topicTags: [String]

    init(id: UUID = .init(), topicTags: [String] = []) {
        self.id = id
        self.startedAt = .now
        self.messages = []
        self.topicTags = topicTags
    }
}

@Model
final class Message {
    var id: UUID
    var role: String        // "user" | "assistant"
    var content: String
    var toolCallsMade: [String]
    var timestamp: Date

    init(
        id: UUID = .init(),
        role: String,
        content: String,
        toolCallsMade: [String] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.toolCallsMade = toolCallsMade
        self.timestamp = .now
    }
}

// MARK: - Draft Types (non-persisted, pending user confirmation)

struct MemoryNoteDraft: Sendable, Identifiable {
    let id = UUID()
    var title: String
    var summary: String
    var topics: [String]
    var importanceScore: Float
    var sourceLabel: String?
}

struct MemoryUpdateDraft: Sendable, Identifiable {
    let id = UUID()
    var noteID: UUID
    var originalTitle: String
    var proposedTitle: String?
    var proposedSummary: String?
    var proposedTopics: [String]?
    var proposedImportanceScore: Float?
}

struct PersonaUpdateDraft: Sendable, Identifiable {
    let id = UUID()
    var proposedPurpose: String?
    var proposedTone: String?
    var proposedValues: [String]?
    var proposedExpertiseAreas: [String]?
}

// MARK: - In-memory Chat Message (for UI thread)

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    var role: String          // "user" | "assistant"
    var content: String
    var toolCallsMade: [String]
    var timestamp: Date
    var isStreaming: Bool

    init(
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

// MARK: - Tool Events (signalled from tools back to UI)

enum ToolEvent: Sendable {
    case toolStarted(String)          // e.g. "Searching memory…"
    case toolCompleted
    case pendingMemoryNote(MemoryNoteDraft)
    case pendingMemoryUpdate(MemoryUpdateDraft)
    case pendingPersonaUpdate(PersonaUpdateDraft)
}
