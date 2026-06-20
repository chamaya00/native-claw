import Foundation
import SwiftData
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Proposes reusable **skills** from things the user repeats (§Phase 6 acceptance: "the
/// assistant proposes a routine the user didn't manually configure"). Runs on-device off
/// the streaming path and writes candidates to the skills inbox as `suggested` — never
/// auto-approved, never run until the user approves. Approval is what makes a skill
/// runnable and exposes it to Siri/Shortcuts.
///
/// This is the Phase-5 `RoutineSuggester` pattern applied to multi-step skills: a skill is
/// a *named* composition of declarative actions, so the suggester proposes a name, a
/// rationale grounded in the user's pattern, and a recipe drawn from the closed
/// `SkillCatalog` vocabulary (never free-form code — App Review §2.5.2).
public struct SkillSuggester: Sendable {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

#if canImport(FoundationModels)
    @Generable
    struct Suggestions {
        @Guide(description: "Reusable multi-step skills worth saving. Empty if nothing clearly recurs.", .maximumCount(2))
        var skills: [SkillCandidate]
    }

    @Generable
    struct SkillCandidate {
        @Guide(description: "A short imperative skill name, e.g. 'Monday review' or 'Travel prep'.")
        var name: String

        @Guide(description: "One sentence on why this was suggested, referencing the user's actual pattern.")
        var rationale: String

        @Guide(description: "What the skill should do, in one sentence.")
        var summary: String
    }
#endif

    /// Run one suggestion pass over recent turns. Self-limiting and best-effort: it needs a
    /// few user turns to have a pattern, dedupes against every existing skill (including
    /// dismissed ones), and never surfaces its own failures. Candidates get the default
    /// `SkillCatalog` recipe so an approved skill is immediately runnable; the user can
    /// refine the steps in the editor.
    @MainActor
    public func suggest(recentMessages: [ChatMessage]) async {
        guard recentMessages.filter({ $0.role == "user" }).count >= 4 else { return }

#if canImport(FoundationModels)
        let transcript = recentMessages
            .suffix(16)
            .map { "\($0.role == "user" ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let context = ModelContext(container)
        let known = SkillStore.knownNames(context: context)

        let session = LanguageModelSession(instructions: Self.instructions)
        let candidates: [SkillCandidate]
        do {
            let response = try await session.respond(
                to: "Conversation:\n\(transcript)\n\nPropose reusable multi-step skills from the user's recurring patterns.",
                generating: Suggestions.self,
                options: GenerationOptions(sampling: .greedy)
            )
            candidates = response.content.skills
        } catch {
            return
        }

        guard !candidates.isEmpty else { return }
        for candidate in candidates {
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let rationale = candidate.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !rationale.isEmpty else { continue }
            guard !known.contains(name.lowercased()) else { continue }
            context.insert(Skill(
                name: name,
                summary: summary,
                rationale: rationale,
                intentRecipe: SkillAction.defaultRecipe,
                status: SkillStatus.suggested.rawValue
            ))
        }
        try? context.save()
#endif
    }

    private static let instructions = """
    You spot recurring multi-step patterns in a conversation and propose turning them into \
    reusable, named skills the user can approve. A good skill is something the user does as a \
    sequence on a rhythm — a Monday review, travel prep, a morning routine — not a single \
    one-off request.

    Only propose a skill when there's a genuine repeated pattern. Do NOT invent skills from a \
    single mention, and do NOT propose generic productivity advice. If nothing clearly \
    recurs, return an empty list.

    Each skill needs a short imperative name, a one-sentence rationale grounded in what the \
    user actually did, and a one-sentence summary of what it should do.
    """
}
