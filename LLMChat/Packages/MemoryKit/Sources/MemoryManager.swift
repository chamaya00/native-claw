import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Distils durable facts about the user from recent conversation and queues them for
/// approval (§Phase 3 curation). This is what turns chat into a growing model of the
/// person — but it does so *honestly*: candidates are written as **unapproved** notes
/// that surface in the memory browser's review inbox. They are never injected into a
/// prompt (retrieval filters on `isUserApproved`) and never indexed into Spotlight
/// until the user approves. Anything the model judges sensitive is additionally flagged
/// and can never be one-tap-trusted by mistake (§B: approval before mutation).
public struct MemoryManager: Sendable {
    private let container: ModelContainer

    public init(container: ModelContainer) {
        self.container = container
    }

#if canImport(FoundationModels)
    @Generable
    struct CandidateFacts {
        @Guide(description: "Durable, reusable facts about the user worth remembering. Empty if nothing rises to that bar.", .maximumCount(5))
        var facts: [Candidate]
    }

    @Generable
    struct Candidate {
        @Guide(description: "A concise title for the fact, e.g. 'Allergic to peanuts' or 'Works at Acme'.")
        var title: String

        @Guide(description: "A synthesized, standalone statement of the fact — not a quote from the conversation.")
        var summary: String

        @Guide(description: "Topic tags for retrieval.", .maximumCount(4))
        var topics: [String]

        @Guide(description: "Importance from 0.0 (trivial) to 1.0 (defining). Use 0.8+ only for facts central to who the user is.")
        var importance: Float

        @Guide(description: "True if the fact concerns health, finances, relationships, precise location, or other sensitive ground.")
        var isSensitive: Bool
    }
#endif

    /// Run one curation pass over the most recent turns. Safe to call opportunistically;
    /// it self-limits, dedupes against what's already stored, and writes only unapproved
    /// candidates. No-op when the transcript is too thin to be worth a model call.
    @MainActor
    public func curate(recentMessages: [ChatMessage]) async {
        let userTurns = recentMessages.filter { $0.role == "user" }
        guard userTurns.count >= 2 else { return }

#if canImport(FoundationModels)
        let transcript = recentMessages
            .suffix(12)
            .map { "\($0.role == "user" ? "User" : "Assistant"): \($0.content)" }
            .joined(separator: "\n")

        let session = LanguageModelSession(instructions: Self.instructions)
        let candidates: [Candidate]
        do {
            let response = try await session.respond(
                to: "Conversation:\n\(transcript)\n\nExtract any durable facts about the user worth remembering long-term.",
                generating: CandidateFacts.self,
                options: GenerationOptions(sampling: .greedy)
            )
            candidates = response.content.facts
        } catch {
            return  // curation is best-effort; never surface its failures to the user
        }

        guard !candidates.isEmpty else { return }
        persist(candidates: candidates)
#endif
    }

#if canImport(FoundationModels)
    @MainActor
    private func persist(candidates: [Candidate]) {
        let context = ModelContext(container)
        let existing = (try? context.fetch(FetchDescriptor<MemoryNote>())) ?? []
        let existingTitles = Set(existing.map { $0.title.lowercased() })

        for candidate in candidates {
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = candidate.summary.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !summary.isEmpty else { continue }
            guard !existingTitles.contains(title.lowercased()) else { continue }

            let note = MemoryNote(
                title: title,
                summary: summary,
                sourceLabel: "Curated \(Date.now.formatted(date: .abbreviated, time: .omitted))",
                topics: candidate.topics,
                importanceScore: min(max(candidate.importance, 0), 1),
                isUserApproved: false,          // → review inbox, never silently trusted
                isSensitive: candidate.isSensitive,
                origin: "curation"
            )
            context.insert(note)
        }
        try? context.save()
    }

    private static let instructions = """
    You distil durable, long-term facts about the user from a conversation. Output only \
    facts that are stable and reusable across future sessions — preferences, relationships, \
    goals, recurring tasks, important constraints.

    Do NOT output:
    - one-off or transient details (today's weather, a single passing question),
    - the assistant's own statements,
    - speculation or anything you're unsure the user actually meant.

    Synthesize each fact as a clean standalone statement, not a quote. If nothing meets \
    this bar, return an empty list. Flag as sensitive anything touching health, finances, \
    relationships, or precise location.
    """
#endif
}
