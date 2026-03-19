import Foundation
import SwiftData

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - UI State

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isResponding: Bool = false
    var error: String?
    var currentConversationID: UUID?

    // MARK: - Dependencies

    let agentService: AgentService
    private let container: ModelContainer

    // MARK: - Init

    init(agentService: AgentService, container: ModelContainer) {
        self.agentService = agentService
        self.container = container
    }

    // MARK: - Session Lifecycle

    func startSession() async {
        do {
            try await agentService.initializeSession()
            createNewConversation()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func endSession() {
        agentService.invalidateSession()
    }

    // MARK: - Sending Messages

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        inputText = ""
        isResponding = true
        error = nil

        let userMessage = ChatMessage(role: "user", content: text)
        messages.append(userMessage)
        persistMessage(userMessage)

        // Insert streaming placeholder
        let placeholder = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(placeholder)
        let placeholderID = placeholder.id

        do {
            var toolCalls: [String] = []
            let response = try await agentService.respond(to: text, toolCallsOut: &toolCalls)

            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].content = response
                messages[idx].toolCallsMade = toolCalls
                messages[idx].isStreaming = false
                persistMessage(messages[idx])
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].content = "Error: \(error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            self.error = error.localizedDescription
        }

        isResponding = false
    }

    // MARK: - Long-press: Save to memory shortcut

    func proposeMemoryFromMessage(_ message: ChatMessage) {
        let draft = MemoryNoteDraft(
            title: String(message.content.prefix(60)),
            summary: message.content,
            topics: [],
            importanceScore: 0.6,
            sourceLabel: "Chat · \(message.timestamp.formatted(date: .abbreviated, time: .shortened))"
        )
        agentService.pendingMemoryNote = draft
    }

    // MARK: - Confirmation Actions

    func confirmMemoryNote() {
        guard let draft = agentService.pendingMemoryNote else { return }
        do {
            try agentService.confirmMemoryNote(draft)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discardMemoryNote() {
        agentService.discardMemoryNote()
    }

    func confirmMemoryUpdate() {
        guard let draft = agentService.pendingMemoryUpdate else { return }
        do {
            try agentService.confirmMemoryUpdate(draft)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discardMemoryUpdate() {
        agentService.discardMemoryUpdate()
    }

    func confirmPersonaUpdate() {
        guard let draft = agentService.pendingPersonaUpdate else { return }
        do {
            try agentService.confirmPersonaUpdate(draft)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func discardPersonaUpdate() {
        agentService.discardPersonaUpdate()
    }

    // MARK: - Conversation Management

    func clearConversation() {
        messages = []
        agentService.invalidateSession()
        createNewConversation()
        Task { await startSession() }
    }

    private func createNewConversation() {
        let context = ModelContext(container)
        let conversation = Conversation()
        context.insert(conversation)
        try? context.save()
        currentConversationID = conversation.id
    }

    private func persistMessage(_ chatMessage: ChatMessage) {
        guard let convID = currentConversationID else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == convID })
        guard let conv = (try? context.fetch(descriptor))?.first else { return }
        let message = Message(
            role: chatMessage.role,
            content: chatMessage.content,
            toolCallsMade: chatMessage.toolCallsMade
        )
        conv.messages.append(message)
        try? context.save()
    }
}
