import Foundation
import SwiftData

// MARK: - SwiftData Models
//
// CloudKit-readiness note (Phase 3): these models keep CloudKit mirroring rules
// in sight even though sync is local-only until Phase 3 — no `@Attribute(.unique)`,
// every stored property is defaulted via its initializer, and relationships are
// optional with an explicit inverse. Phase 3 flips on the CloudKit container.

@Model
public final class Persona {
    public var name: String
    public var vibe: String
    public var values: [String]
    public var expertiseAreas: [String]
    public var updatedAt: Date

    public init(
        name: String = "Claw",
        vibe: String,
        values: [String],
        expertiseAreas: [String]
    ) {
        self.name = name
        self.vibe = vibe
        self.values = values
        self.expertiseAreas = expertiseAreas
        self.updatedAt = .now
    }
}

@Model
public final class MemoryNote {
    public var id: UUID
    public var title: String
    public var summary: String
    public var sourceLabel: String?
    public var topics: [String]
    public var importanceScore: Float
    public var isUserApproved: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
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
public final class ImportedFile {
    public var id: UUID
    public var filename: String
    public var contentPreview: String  // first ~500 chars
    public var relativePath: String    // path relative to Documents directory
    public var importedAt: Date
    public var lastAccessedAt: Date?

    public init(
        id: UUID = .init(),
        filename: String,
        contentPreview: String,
        relativePath: String
    ) {
        self.id = id
        self.filename = filename
        self.contentPreview = contentPreview
        self.relativePath = relativePath
        self.importedAt = .now
        self.lastAccessedAt = nil
    }
}

@Model
public final class Conversation {
    public var id: UUID
    public var startedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    public var messages: [Message]
    public var topicTags: [String]

    public init(id: UUID = .init(), topicTags: [String] = []) {
        self.id = id
        self.startedAt = .now
        self.messages = []
        self.topicTags = topicTags
    }
}

@Model
public final class Message {
    public var id: UUID
    public var role: String        // "user" | "assistant"
    public var content: String
    public var toolCallsMade: [String]
    public var timestamp: Date
    public var conversation: Conversation?

    public init(
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
