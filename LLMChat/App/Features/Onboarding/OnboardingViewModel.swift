import Foundation
import SwiftData
import MemoryKit
import AgentKit

@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - State

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isResponding: Bool = false
    var error: String?
    var showSavedToast: Bool = false
    var isComplete: Bool = false
    var personaPreview: PersonaPreview?

    /// Onboarding stages. After the persona is shaped we offer a personalized "magic moment"
    /// built from data already on the device (§Phase 8) before handing off to the chat.
    enum Stage { case chatting, magicOffer, revealing, revealed }
    var stage: Stage = .chatting

    struct PersonaPreview {
        var name: String
        var vibe: String
        var values: [String]
        var expertiseAreas: [String]
    }

    // MARK: - Dependencies

    private let engine: ConversationEngine
    private let container: ModelContainer

    init(engine: ConversationEngine, container: ModelContainer) {
        self.engine = engine
        self.container = container
    }

    // MARK: - Lifecycle

    func startOnboarding() async {
        engine.startOnboarding()
        messages = [ChatMessage(
            role: "assistant",
            content: "Hi. I don't have a name yet, no personality, nothing. Let's fix that. What would you like to call me?"
        )]
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isResponding else { return }

        inputText = ""
        isResponding = true
        error = nil

        messages.append(ChatMessage(role: "user", content: text))

        let placeholder = ChatMessage(role: "assistant", content: "", isStreaming: true)
        messages.append(placeholder)
        let placeholderID = placeholder.id

        do {
            let response = try await engine.onboardingRespond(to: text)
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].content = response
                messages[idx].isStreaming = false
            }

            if messages.filter({ $0.role == "user" }).count >= 3 && personaPreview == nil {
                await generatePersonaPreview()
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

    // MARK: - Persona Extraction

    func generatePersonaPreview() async {
        do {
            let draft = try await engine.extractPersona()

            var summaryParts = ["**\(draft.name)**", "vibe: \(draft.vibe)"]
            if !draft.values.isEmpty {
                summaryParts.append("values: \(draft.values.joined(separator: ", "))")
            }
            if !draft.expertiseAreas.isEmpty {
                summaryParts.append("into: \(draft.expertiseAreas.joined(separator: ", "))")
            }

            messages.append(ChatMessage(
                role: "assistant",
                content: "alright, got it — " + summaryParts.joined(separator: ", ") + "."
            ))

            try savePersona(draft)
            showSavedToast = true
            try await Task.sleep(for: .seconds(2.5))
            showSavedToast = false
            // Offer the personalized first impression before entering the app (§Phase 8).
            stage = .magicOffer
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Magic moment (Phase 8)

    /// Request calendar + reminders access (value already framed in the UI), read today's data
    /// on-device, and surface one strikingly relevant observation. Degrades silently if access
    /// is denied or the day is empty.
    func revealMagicMoment() async {
        stage = .revealing
        let access = await MagicMomentService.requestAccess()

        var observation: String?
        if access.anyGranted {
            observation = await MagicMomentService.generateObservation(persona: currentPersona())
        }

        if let observation {
            messages.append(ChatMessage(role: "assistant", content: observation))
            Metrics.increment(.magicMomentShown, in: ModelContext(container))
        } else {
            let name = currentPersona()?.name ?? "I"
            messages.append(ChatMessage(
                role: "assistant",
                content: "\(name == "I" ? "I'm" : name + " is") all set. Tell me what's on your plate and we'll get going."
            ))
        }
        stage = .revealed
    }

    /// Skip the magic moment and enter the app.
    func skipMagicMoment() {
        finishOnboarding()
    }

    /// Complete onboarding and hand off to the chat. Records first-time activation.
    func finishOnboarding() {
        Metrics.recordOnce(.activated, in: ModelContext(container))
        isComplete = true
    }

    private func currentPersona() -> Persona? {
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<Persona>()))?.first
    }

    // MARK: - Persist Persona

    private func savePersona(_ draft: PersonaDraft) throws {
        let context = ModelContext(container)

        // Replace any existing persona (Reconfigure re-runs onboarding).
        for existing in (try? context.fetch(FetchDescriptor<Persona>())) ?? [] {
            context.delete(existing)
        }

        context.insert(Persona(
            name: draft.name,
            vibe: draft.vibe,
            values: draft.values,
            expertiseAreas: draft.expertiseAreas
        ))
        try context.save()
    }
}
