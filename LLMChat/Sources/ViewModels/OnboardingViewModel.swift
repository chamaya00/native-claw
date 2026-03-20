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
    var showSavedToast: Bool = false
    var isComplete: Bool = false

    struct PersonaPreview {
        var name: String
        var vibe: String
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
            let (name, vibe, values, areas) = try await agentService.extractPersonaDraft()

            var summaryParts = ["**\(name)**", "vibe: \(vibe)"]
            if !values.isEmpty {
                summaryParts.append("values: \(values.joined(separator: ", "))")
            }
            if !areas.isEmpty {
                summaryParts.append("into: \(areas.joined(separator: ", "))")
            }

            let previewMessage = ChatMessage(
                role: "assistant",
                content: "alright, got it — " + summaryParts.joined(separator: ", ") + "."
            )
            messages.append(previewMessage)

            try savePersona(name: name, vibe: vibe, values: values, expertiseAreas: areas)
            showSavedToast = true
            try await Task.sleep(for: .seconds(2.5))
            showSavedToast = false
            isComplete = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Persist Persona

    private func savePersona(name: String, vibe: String, values: [String], expertiseAreas: [String]) throws {
        let context = ModelContext(container)

        // Remove any existing persona
        let existing = (try? context.fetch(FetchDescriptor<Persona>())) ?? []
        for p in existing { context.delete(p) }

        let persona = Persona(
            name: name,
            vibe: vibe,
            values: values,
            expertiseAreas: expertiseAreas
        )
        context.insert(persona)
        try context.save()
    }
}
