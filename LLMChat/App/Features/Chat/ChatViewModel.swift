import Foundation
import SwiftData
import PDFKit
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

    /// On-device text/barcode digest of an attached image, folded into the next send
    /// (Phase 2 multimodal). We keep the digest, not the pixels, to protect the 4K budget.
    var pendingImageDigest: String?
    var pendingImageName: String?
    var isProcessingImage: Bool = false

    var hasPendingImage: Bool { pendingImageDigest != nil }

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
        let digest = pendingImageDigest
        guard (!text.isEmpty || digest != nil), !isResponding else { return }

        inputText = ""
        isResponding = true
        error = nil

        // The user sees their words (plus an image marker); the model gets the words
        // preceded by the on-device-extracted image content.
        let displayText: String
        if let name = pendingImageName {
            displayText = text.isEmpty ? "📷 \(name)" : "📷 \(name)\n\n\(text)"
        } else {
            displayText = text
        }
        let sentText: String
        if let digest {
            sentText = "[Image attached — extracted on-device]\n\(digest)\n\n\(text.isEmpty ? "Help me with this image." : text)"
        } else {
            sentText = text
        }
        let hadImage = digest != nil
        pendingImageDigest = nil
        pendingImageName = nil

        messages.append(ChatMessage(role: "user", content: displayText))

        // Streaming placeholder bound to the response snapshots.
        let placeholder = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(placeholder)
        let placeholderID = placeholder.id

        do {
            for try await snapshot in engine.streamResponse(to: sentText, hasImage: hadImage) {
                if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                    messages[idx].content = snapshot
                }
            }
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].isStreaming = false
                messages[idx].toolCallsMade = engine.lastTurnToolCalls
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

    // MARK: - Image Attachment (Phase 2 multimodal)

    /// Pre-process an attached image to compact text on-device (OCR + barcodes) so it can
    /// ride the next message without consuming the 4K window with raw pixels.
    func attachImage(data: Data, name: String) async {
        isProcessingImage = true
        error = nil
        defer { isProcessingImage = false }
        do {
            let result = try await ImageProcessor.digest(from: data)
            if result.isEmpty {
                error = "No text or barcodes were found in that image."
                return
            }
            pendingImageDigest = result.promptContext()
            pendingImageName = name
        } catch {
            self.error = error.localizedDescription
        }
    }

    func clearPendingImage() {
        pendingImageDigest = nil
        pendingImageName = nil
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

    func confirmCalendarEvent() {
        Task {
            do { try await approvalGate.confirmCalendarEvent() }
            catch { self.error = error.localizedDescription }
        }
    }
    func discardCalendarEvent() { approvalGate.discardCalendarEvent() }

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
            if let document = PDFDocument(url: url), let text = document.string, !text.isEmpty {
                return text
            }
            return "[PDF \(url.lastPathComponent) has no extractable text — it may be a scanned image. Attach a page as a photo to OCR it.]"
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
