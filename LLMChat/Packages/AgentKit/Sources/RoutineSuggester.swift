import Foundation
import SwiftData
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Notices recurring patterns in the conversation and proposes turning them into routines
/// (§Phase 5 proactivity). Runs on-device off the streaming path and writes candidates to
/// the in-app inbox as **suggested** — never a push, never auto-approved. Approval is what
/// turns a suggestion into a routine that may notify, which is the single biggest churn
/// risk turned into a trust feature (§Phase 5 rationale).
public struct RoutineSuggester: Sendable {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

#if canImport(FoundationModels)
    @Generable
    struct Suggestions {
        @Guide(description: "Recurring tasks worth turning into a saved routine. Empty if nothing clearly recurs.", .maximumCount(2))
        var routines: [RoutineCandidate]
    }

    @Generable
    struct RoutineCandidate {
        @Guide(description: "A short imperative routine name, e.g. 'Morning briefing' or 'Weekly review'.")
        var title: String

        @Guide(description: "One sentence on why this was suggested, referencing the user's actual pattern.")
        var rationale: String

        @Guide(description: "Natural-language schedule, e.g. 'weekdays 8am' or 'Sunday evening'. Empty if unclear.")
        var scheduleHint: String
    }
#endif

    /// Run one suggestion pass over recent turns. Self-limiting and best-effort: it needs a
    /// few user turns to have a pattern, dedupes against every existing routine (including
    /// dismissed ones, so a rejection sticks), and never surfaces its own failures.
    @MainActor
    public func suggest(recentMessages: [ChatMessage]) async {
        guard recentMessages.filter({ $0.role == "user" }).count >= 4 else { return }

#if canImport(FoundationModels)
        let transcript = recentMessages
            .suffix(16)
            .map { "\($0.role == "user" ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let context = ModelContext(container)
        // Every routine title we already know — suggested, approved, *or dismissed* — so a
        // dismissal is a durable negative signal and we never re-propose it.
        let known = Set(((try? context.fetch(FetchDescriptor<SuggestedRoutine>())) ?? [])
            .map { $0.title.lowercased() })

        let session = LanguageModelSession(instructions: Self.instructions)
        let candidates: [RoutineCandidate]
        do {
            let response = try await session.respond(
                to: "Conversation:\n\(transcript)\n\nPropose reusable routines from the user's recurring patterns.",
                generating: Suggestions.self,
                options: GenerationOptions(sampling: .greedy)
            )
            candidates = response.content.routines
        } catch {
            return
        }

        guard !candidates.isEmpty else { return }
        for candidate in candidates {
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let rationale = candidate.rationale.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !rationale.isEmpty else { continue }
            guard !known.contains(title.lowercased()) else { continue }
            let hint = candidate.scheduleHint.trimmingCharacters(in: .whitespacesAndNewlines)
            context.insert(SuggestedRoutine(
                title: title,
                rationale: rationale,
                status: RoutineStatus.suggested.rawValue,
                scheduleHint: hint.isEmpty ? nil : hint
            ))
        }
        try? context.save()
#endif
    }

    private static let instructions = """
    You spot recurring patterns in a conversation and propose turning them into reusable \
    routines the user can approve. A good routine is something the user does or asks about \
    repeatedly on a rhythm — a morning briefing, a weekly review, a recurring prep checklist.

    Only propose a routine when there's a genuine repeated pattern. Do NOT invent routines \
    from a single mention, and do NOT propose generic productivity advice. If nothing clearly \
    recurs, return an empty list.

    Each routine needs a short imperative name, a one-sentence rationale grounded in what the \
    user actually did, and a schedule hint when one is implied (leave it empty otherwise).
    """
}
