import Foundation
import SwiftData
import EventKit
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Builds the proactive daily brief for an approved briefing routine (§Phase 5). Reads
/// today's calendar (read-only — no approval needed) plus the top approved memories, then
/// asks the model for a short, useful digest.
///
/// Routed through `ModelRouter` as a `.briefing` task so it escalates to PCC for synthesis
/// when policy allows and falls back to on-device otherwise — the same policy, metering, and
/// transparency every chat turn uses (§Phase 4). Generation itself runs on whatever tier the
/// router *binds*, which today is on-device (the documented cloud-binding seam).
public struct BriefingService: Sendable {
    private let container: ModelContainer
    private let budget = ContextBudget()

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Generate the brief, or `nil` when there's nothing worth saying (no events, no memory)
    /// or the model is unavailable. Best-effort: never throws into the background handler.
    @MainActor
    public func generateBrief(now: Date = .now) async -> String? {
        let events = todaysEvents(now: now)
        let memories = topMemories()
        guard !events.isEmpty || !memories.isEmpty else { return nil }

        let context = """
        Today's calendar:
        \(events.isEmpty ? "Nothing scheduled." : events.joined(separator: "\n"))

        What you know about the user:
        \(memories.isEmpty ? "Nothing notable." : memories.map { "- \($0.title): \($0.summary)" }.joined(separator: "\n"))
        """

        // Route the briefing through policy (applies the privacy lock, meters PCC, and
        // records the tier for transparency) even though the bound tier runs on-device.
        let router = ModelRouter(container: container)
        _ = router.resolve(task: .briefing, estimatedPromptTokens: budget.estimatedTokens(context))

#if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: Self.instructions)
        do {
            let response = try await session.respond(
                to: "Write today's brief from this context:\n\n\(context)",
                options: GenerationOptions(sampling: .greedy)
            )
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
#else
        return nil
#endif
    }

    // MARK: - Sources (read-only)

    /// Today's events, if calendar access is already granted. Background runs never prompt —
    /// if access isn't there yet, the brief simply leans on memory.
    private func todaysEvents(now: Date) -> [String] {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return [] }

        let store = EKEventStore()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { event in
                let time = event.isAllDay
                    ? "All day"
                    : event.startDate.formatted(date: .omitted, time: .shortened)
                return "\(time): \(event.title ?? "Untitled")"
            }
    }

    @MainActor
    private func topMemories() -> [MemoryNote] {
        let context = ModelContext(container)
        return searchMemories(query: "today priorities goals plans", context: context, limit: 5)
    }

    private static let instructions = """
    You write a short morning brief for the user — two to four sentences, plain text, no \
    markdown. Lead with what matters today: their schedule and anything you know about their \
    current priorities. Be concrete and useful, never generic. If the day looks light, say so \
    briefly rather than padding.
    """
}
