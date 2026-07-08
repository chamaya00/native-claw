import Foundation
import SwiftData
import PDFKit
import MemoryKit
import AgentKit
import SkillsKit
import VoiceKit

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

    /// Whether the focused research subagent is active (§Phase 6 Dynamic Profiles). When on,
    /// turns run in an isolated context and are not saved to the main conversation.
    var isResearchMode: Bool = false

    /// Test override that pins main-chat turns to one tier so the same prompt can be compared
    /// on-device vs Private Cloud Compute (§Phase 4). `nil` = normal policy routing. The tier
    /// chip under each reply shows where the turn actually ran.
    var forcedTier: ModelTier? {
        get { engine.forcedTier }
        set { engine.forcedTier = newValue }
    }

    // MARK: - Voice (Phase 7)

    /// On-device dictation (SpeechAnalyzer) and TTS (AVSpeechSynthesizer). All processing stays
    /// on device — no audio or text leaves the phone.
    let transcriber = VoiceTranscriber()
    let speaker = SpeechSpeaker()

    /// When on, the assistant's final reply is spoken aloud.
    var isVoiceModeOn: Bool = false
    /// Whether on-device speech recognition is usable for the current language (checked on appear).
    var isVoiceSupported: Bool = false

    var isListening: Bool { transcriber.isListening }

    /// Turns since the last skill-suggestion pass. Skills are proposed periodically off the
    /// streaming path (mirrors routine suggestion), at a slightly longer cadence.
    private var turnsSinceSkillSuggestion = 0
    private static let skillSuggestionInterval = 8

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
        speaker.stop()
        Task { await transcriber.stop() }
        engine.invalidate()
    }

    // MARK: - Sending Messages

    func sendMessage() async {
        // End dictation before sending so the captured text is final and the mic releases.
        if transcriber.isListening { await transcriber.stop() }
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
                messages[idx].tierLabel = engine.lastResponseTier?.shortLabel
                messages[idx].tierSystemImage = engine.lastResponseTier?.systemImage
                // Voice mode: read the finished reply aloud (§Phase 7, on-device TTS).
                if isVoiceModeOn { speaker.speak(messages[idx].content) }
            }
        } catch {
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].content = "Error: \(error.localizedDescription)"
                messages[idx].isStreaming = false
            }
            self.error = error.localizedDescription
        }

        isResponding = false
        maybeSuggestSkills()
    }

    // MARK: - Voice control (Phase 7)

    /// Resolve whether on-device dictation is usable for the current language. Called on appear so
    /// the mic button can disable gracefully on unsupported locales/SDKs (§B availability gating).
    func refreshVoiceSupport() async {
        isVoiceSupported = await VoiceTranscriber.isSupported()
    }

    /// Start/stop dictation. While listening, the transcript is mirrored into the input field by
    /// the view; stopping leaves the text in place for the user to review or send.
    func toggleDictation() {
        if speaker.isSpeaking { speaker.stop() }
        Task { await transcriber.toggle() }
    }

    /// Mirror the live transcript into the input field while dictating.
    func syncDictationToInput() {
        if transcriber.isListening { inputText = transcriber.transcript }
    }

    /// Toggle whether replies are spoken aloud. Turning it off stops any in-flight speech.
    func toggleVoiceMode() {
        isVoiceModeOn.toggle()
        if !isVoiceModeOn { speaker.stop() }
    }

    // MARK: - Research mode (Phase 6 Dynamic Profiles)

    /// Toggle the focused research subagent. Switching profiles re-seats the relevant session;
    /// research turns run isolated so the main chat stays clean.
    func toggleResearchMode() {
        isResearchMode.toggle()
        let target: ConversationProfile = isResearchMode ? .research : .assistant
        Task { await engine.activateProfile(target) }
    }

    // MARK: - Skill suggestion (Phase 6)

    /// Periodically propose reusable skills from recurring patterns (§Phase 6). Off the
    /// streaming path, self-limiting, best-effort — candidates land in the in-app skills
    /// inbox as `suggested`, never auto-approved and never run. Skipped during research mode.
    private func maybeSuggestSkills() {
        guard !isResearchMode else { return }
        turnsSinceSkillSuggestion += 1
        guard turnsSinceSkillSuggestion >= Self.skillSuggestionInterval else { return }
        turnsSinceSkillSuggestion = 0
        let recent = messages
        let container = self.container
        Task { await SkillSuggester(container: container).suggest(recentMessages: recent) }
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

    // MARK: - Preference Picker (Phase 5)

    /// The pending A/B style choice, surfaced as a card under the chat.
    var pendingPreferenceChoice: PreferenceChoice? { engine.preferenceLearner.pendingChoice }

    /// Record the user's pick and re-seat the session so the learned style applies right away.
    func choosePreference(pickedA: Bool) {
        guard let choice = engine.preferenceLearner.pendingChoice else { return }
        engine.preferenceLearner.record(choice: choice, pickedA: pickedA)
        Task { await engine.applyLearnedPreferences() }
    }

    func skipPreference() { engine.preferenceLearner.skip() }

    // MARK: - Conversation Management

    func clearConversation() {
        messages = []
        isResearchMode = false
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
