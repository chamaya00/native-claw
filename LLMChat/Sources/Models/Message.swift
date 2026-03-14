import Foundation

enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
}

struct Message: Identifiable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}
