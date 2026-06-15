import Foundation
import SwiftData
import MemoryKit
import AgentKit

@Observable
@MainActor
final class ChatViewModel {

    // MARK: - UI State

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isResponding: Bool = false
    var error: String?

    // MARK: - Dependencies

    let engine: ConversationEngine
    private let container: ModelContainer

    var approvalGate: ApprovalGate { engine.approvalGate }

    init(engine: ConversationEngine, container: ModelContainer) {
        self.engine = engine
        self.container = container
    }

    // MARK: - Session Lifecycle

    func startSession() async {
        do {
            try await engine.start()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func endSession() {
        engine.invalidate()
    }

    // MARK: - Sending Messages

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        inputText = ""
        isResponding = true
        error = nil

        messages.append(ChatMessage(role: "user", content: text))

        // Streaming placeholder bound to the response snapshots.
        let placeholder = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(placeholder)
        let placeholderID = placeholder.id

        do {
            for try await snapshot in engine.streamResponse(to: text) {
                if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                    messages[idx].content = snapshot
                }
            }
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].isStreaming = false
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
        approvalGate.pendingMemoryNote = MemoryNoteDraft(
            title: String(message.content.prefix(60)),
            summary: message.content,
            topics: [],
            importanceScore: 0.6,
            sourceLabel: "Chat · \(message.timestamp.formatted(date: .abbreviated, time: .shortened))"
        )
    }

    // MARK: - Confirmation Actions

    func confirmMemoryNote() { run { try self.approvalGate.confirmMemoryNote() } }
    func discardMemoryNote() { approvalGate.discardMemoryNote() }

    func confirmMemoryUpdate() { run { try self.approvalGate.confirmMemoryUpdate() } }
    func discardMemoryUpdate() { approvalGate.discardMemoryUpdate() }

    func confirmPersonaUpdate() { run { try self.approvalGate.confirmPersonaUpdate() } }
    func discardPersonaUpdate() { approvalGate.discardPersonaUpdate() }

    func confirmReminder() {
        Task {
            do { try await approvalGate.confirmReminder() }
            catch { self.error = error.localizedDescription }
        }
    }
    func discardReminder() { approvalGate.discardReminder() }

    // MARK: - Conversation Management

    func clearConversation() {
        messages = []
        Task { await engine.clearConversation() }
    }

    // MARK: - File Import

    func importFile(from url: URL) {
        do {
            let text = try Self.extractText(from: url)
            let preview = String(text.prefix(500))
            let filename = url.lastPathComponent

            let destFilename = "\(UUID().uuidString)_\(filename)"
            let destURL = URL.documentsDirectory.appending(path: destFilename)
            try Data(contentsOf: url).write(to: destURL)

            let context = ModelContext(container)
            context.insert(ImportedFile(filename: filename, contentPreview: preview, relativePath: destFilename))
            try context.save()

            messages.append(ChatMessage(
                role: "assistant",
                content: "I've loaded **\(filename)**. I can reference it when relevant."
            ))
        } catch {
            self.error = "Failed to import file: \(error.localizedDescription)"
        }
    }

    private static func extractText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        if url.pathExtension.lowercased() == "pdf" {
            // PDF text extraction lands with the multimodal capture work in Phase 2.
            return "[PDF content from \(url.lastPathComponent) — text extraction arrives in Phase 2 (OCR/Vision pre-processing).]"
        }

        if url.pathExtension.lowercased() == "rtf",
           let attrStr = try? NSAttributedString(
               data: data,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return attrStr.string
        }

        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }

    // MARK: - Helpers

    private func run(_ work: () throws -> Void) {
        do { try work() } catch { self.error = error.localizedDescription }
    }
}
