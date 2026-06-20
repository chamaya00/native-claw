import Foundation
import SwiftData

// MARK: - SwiftData Models
//
// CloudKit mirroring rules (live since Phase 3 — the store mirrors to the user's private
// CloudKit database):
//   • no `@Attribute(.unique)` anywhere;
//   • every scalar attribute carries an **inline** default value (CloudKit requires a
//     default on non-optional attributes, and SwiftData reads the default from the
//     property declaration — an `init` default is not enough), or is optional;
//   • to-one relationships are optional with an explicit inverse.

@Model
public final class Persona {
    public var name: String = "Claw"
    public var vibe: String = ""
    public var values: [String] = []
    public var expertiseAreas: [String] = []
    public var updatedAt: Date = Date.now

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
    public var id: UUID = UUID()
    public var title: String = ""
    public var summary: String = ""
    public var sourceLabel: String?
    public var topics: [String] = []
    public var importanceScore: Float = 0.5
    public var isUserApproved: Bool = false
    /// Set by the curation pass when a candidate touches sensitive ground (health,
    /// finances, relationships, location). Sensitive facts are *never* auto-approved —
    /// they wait in the review inbox and the user decides (§Phase 3 guardrail).
    public var isSensitive: Bool = false
    /// "user" (typed/confirmed by the user) | "curation" (distilled by MemoryManager).
    public var origin: String = "user"
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = .init(),
        title: String,
        summary: String,
        sourceLabel: String? = nil,
        topics: [String] = [],
        importanceScore: Float = 0.5,
        isUserApproved: Bool = false,
        isSensitive: Bool = false,
        origin: String = "user"
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.sourceLabel = sourceLabel
        self.topics = topics
        self.importanceScore = importanceScore
        self.isUserApproved = isUserApproved
        self.isSensitive = isSensitive
        self.origin = origin
        self.createdAt = .now
        self.updatedAt = .now
    }
}

@Model
public final class ImportedFile {
    public var id: UUID = UUID()
    public var filename: String = ""
    public var contentPreview: String = ""   // first ~500 chars
    public var relativePath: String = ""     // path relative to Documents directory
    public var importedAt: Date = Date.now
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
    public var id: UUID = UUID()
    public var startedAt: Date = Date.now
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    public var messages: [Message] = []
    public var topicTags: [String] = []

    public init(id: UUID = .init(), topicTags: [String] = []) {
        self.id = id
        self.startedAt = .now
        self.messages = []
        self.topicTags = topicTags
    }
}

@Model
public final class Message {
    public var id: UUID = UUID()
    public var role: String = "user"        // "user" | "assistant"
    public var content: String = ""
    public var toolCallsMade: [String] = []
    public var timestamp: Date = Date.now
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
