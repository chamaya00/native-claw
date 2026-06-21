import Foundation
import SwiftData
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A one-shot, headless assistant turn for system-surface invocation (§Phase 7).
///
/// When Claw is invoked from Siri / the Action button / Spotlight / Shortcuts there's no live
/// `ConversationEngine` and no streaming UI — just a prompt in and an answer out. This responder
/// builds the same persona + retrieved-memory instructions the chat uses, runs a single on-device
/// `respond(to:)`, and returns text. It is deliberately **read-only**: no tools are attached and
/// nothing is persisted, so an out-of-app invocation can never perform an unapproved mutation
/// (§B approval-before-mutation). It runs on the private on-device tier (the §B default); routing a
/// large out-of-app ask up to PCC is the same one-function seam documented for Phase 4.
public enum AssistantQuickResponder {

    /// Produce a single assistant reply to `prompt`, or a friendly fallback when the on-device
    /// model isn't available. Never throws — system intents want a speakable answer, not an error.
    @MainActor
    public static func respond(to prompt: String, container: ModelContainer) async -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Ask me something and I'll help." }

        let availability = AvailabilityService()
        guard availability.isAvailable else { return availability.state.userMessage }

#if canImport(FoundationModels)
        let context = ModelContext(container)
        let personaStore = PersonaStore(container: container)
        let persona = personaStore.currentPersona()

        // A small, relevant memory seed so an out-of-app answer is still personalized — using the
        // same deterministic scorer the chat turn uses (top-k only, never the whole store).
        let memories = searchMemories(query: trimmed, context: context, limit: 3)
        let instructions = personaStore.systemInstructions(
            persona: persona,
            topMemories: memories
        )

        let session = LanguageModelSession(instructions: instructions)
        do {
            // Greedy sampling for a stable, repeatable system-surface answer.
            let response = try await session.respond(
                to: trimmed,
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content
        } catch {
            return "Sorry, I couldn't answer that just now."
        }
#else
        return "Claw needs a device with Apple Intelligence to answer."
#endif
    }
}
