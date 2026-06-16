import Foundation
import SwiftData
import MemoryKit

/// Owns the persona/system-prompt that seeds each `LanguageModelSession`.
/// Kept compact deliberately — instructions are billed against the 4K window.
public struct PersonaStore {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    public func currentPersona() -> Persona? {
        let context = ModelContext(container)
        return (try? context.fetch(FetchDescriptor<Persona>()))?.first
    }

    /// Build the session instructions from the persona plus a small set of
    /// retrieved memories. `summary` carries a condensed transcript when the
    /// session is re-seated after a context-window overflow (see ContextBudget).
    public func systemInstructions(
        persona: Persona?,
        topMemories: [MemoryNote],
        condensedSummary: String? = nil
    ) -> String {
        var prompt = """
        You are Claw, a private on-device AI agent. Your persona and purpose are defined in your memory and loaded at the start of each session.

        Rules:
        - You have access to tools. Use them proactively when they would help you give a better answer.
        - Always search memory before answering questions about the user's interests, goals, or past conversations.
        - Never write to memory, update the persona, or create reminders without proposing the change first and getting user confirmation.
        - Prefer short, precise responses. No filler. No hedging.
        - If you cannot do something with your available tools, say so clearly and suggest what the user could do instead.
        - All processing is on-device and private. Never reference external services.
        """

        if let persona {
            prompt += """


            Your current persona:
            - Name: \(persona.name)
            - Vibe: \(persona.vibe)
            - Values: \(persona.values.joined(separator: ", "))
            - Expertise areas: \(persona.expertiseAreas.joined(separator: ", "))
            """
        }

        if !topMemories.isEmpty {
            prompt += "\n\nRecent context from memory:\n"
            for memory in topMemories {
                prompt += "- \(memory.title): \(memory.summary)\n"
            }
        }

        if let condensedSummary, !condensedSummary.isEmpty {
            prompt += "\n\nSummary of the conversation so far:\n\(condensedSummary)"
        }

        return prompt
    }
}
