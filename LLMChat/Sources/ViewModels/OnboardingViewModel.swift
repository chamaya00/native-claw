import Foundation
import SwiftData

@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - State

    var messages: [ChatMessage] = []
    var inputText: String = ""
    var isResponding: Bool = false
    var error: String?
    var personaPreview: PersonaPreview?
    var isComplete: Bool = false

    struct PersonaPreview {
        var name: String
        var purpose: String
        var tone: String
        var values: [String]
        var expertiseAreas: [String]
    }

    // MARK: - Dependencies

    private let agentService: AgentService
    private let container: ModelContainer

    // MARK: - Init

    init(agentService: AgentService, container: ModelContainer) {
        self.agentService = agentService
        self.container = container
    }

    // MARK: - Lifecycle

    func startOnboarding() async {
        agentService.initOnboardingSession()

        // Initial message — the assistant has no name or identity yet
        let intro = ChatMessage(
            role: "assistant",
            content: "Hi. I don't have a name yet, no personality, nothing. Let's fix that. What would you like to call me?"
        )
        messages = [intro]
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
            let response = try await agentService.onboardingRespond(to: text)
            if let idx = messages.firstIndex(where: { $0.id == placeholderID }) {
                messages[idx].content = response
                messages[idx].isStreaming = false
            }

            // Heuristic: if the conversation is long enough, offer to generate persona
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
            let (name, purpose, tone, values, areas) = try await agentService.extractPersonaDraft()
            personaPreview = PersonaPreview(
                name: name,
                purpose: purpose,
                tone: tone,
                values: values,
                expertiseAreas: areas
            )

            let previewMessage = ChatMessage(
                role: "assistant",
                content: "Here's who I'll be for you. Does this feel right?\n\n**Name:** \(name)\n**Purpose:** \(purpose)\n**Tone:** \(tone)\n**Values:** \(values.joined(separator: ", "))\n**Focus areas:** \(areas.joined(separator: ", "))"
            )
            messages.append(previewMessage)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Confirm and Write Persona

    func confirmPersona() throws {
        guard let preview = personaPreview else { return }
        let context = ModelContext(container)

        // Remove any existing persona
        let existing = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
        for p in existing { context.delete(p) }

        let persona = Persona(
            name: preview.name,
            purpose: preview.purpose,
            tone: preview.tone,
            values: preview.values,
            expertiseAreas: preview.expertiseAreas
        )
        context.insert(persona)
        try context.save()
        isComplete = true
    }
}
