import Foundation
import SwiftData
import EventKit
import MemoryKit
import AgentKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// The result of running a skill end-to-end.
public struct SkillRunResult: Sendable {
    /// Human-readable text to show the user (the assembled output of the recipe).
    public let text: String
    /// Whether every known step produced output — the signal `SkillStore.recordRun` feeds
    /// into `successRate`, which the self-improvement loop reasons from.
    public let succeeded: Bool

    public init(text: String, succeeded: Bool) {
        self.text = text
        self.succeeded = succeeded
    }
}

/// Runs an approved `Skill`'s declarative recipe on-device (§Phase 6).
///
/// "Runs multi-step work reliably" is realised by walking the ordered `SkillAction` recipe
/// and performing each known step — calendar/memory reads and an on-device synthesis — then
/// recording the outcome so a skill's `successRate` accrues from real runs. Every step is
/// read-only or already-approved (see `SkillCatalog`), so a run never performs an
/// unapproved mutation. Generation is routed through `ModelRouter` as a `.briefing` task so
/// it inherits the full Phase-4 policy (privacy lock, PCC metering, transparency); the bound
/// tier runs on-device today (the documented cloud-binding seam).
@MainActor
public struct SkillRunner {
    private let container: ModelContainer
    private let budget = ContextBudget()

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Run the skill, record the outcome against its `successRate`, and return the result.
    @discardableResult
    public func run(_ skill: Skill, now: Date = .now) async -> SkillRunResult {
        let context = ModelContext(container)
        // Re-resolve the skill into this runner's own context so run-tracking persists on the
        // right object — the caller's `skill` belongs to a different context, and saving a
        // different context wouldn't write its mutations.
        let skillID = skill.id
        let name = skill.name
        let working = (try? context.fetch(
            FetchDescriptor<Skill>(predicate: #Predicate { $0.id == skillID })
        ))?.first
        let actions = SkillAction.recipe(from: working?.intentRecipe ?? skill.intentRecipe)

        guard !actions.isEmpty else {
            if let working { SkillStore.recordRun(working, succeeded: false, context: context) }
            return SkillRunResult(
                text: "“\(name)” has no steps yet. Edit it to add some.",
                succeeded: false
            )
        }

        // Walk the recipe, collecting each step's output. `planDay` synthesises over what
        // the earlier steps gathered, so order matters (the recipe is the plan).
        var sections: [String] = []
        var allProduced = true
        var gathered: [String] = []

        for action in actions {
            let output: String
            switch action {
            case .checkCalendar:
                output = todaysEvents(now: now)
            case .reviewMemory:
                output = topMemories(context: context)
            case .dailyBrief:
                output = await BriefingService(container: container).generateBrief(now: now) ?? ""
            case .planDay:
                output = await synthesisePlan(from: gathered)
            }

            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                allProduced = false
            } else {
                gathered.append("\(action.displayName):\n\(trimmed)")
                sections.append("**\(action.displayName)**\n\(trimmed)")
            }
        }

        let text = sections.isEmpty
            ? "I ran “\(name)” but there was nothing to report right now."
            : sections.joined(separator: "\n\n")
        let succeeded = !sections.isEmpty && allProduced
        if let working { SkillStore.recordRun(working, succeeded: succeeded, context: context) }
        return SkillRunResult(text: text, succeeded: succeeded)
    }

    // MARK: - Steps (read-only)

    /// Today's events, if calendar access is already granted. Never prompts — a skill run
    /// (including from the background or Shortcuts) leans on what's already authorised.
    private func todaysEvents(now: Date) -> String {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else { return "" }

        let store = EKEventStore()
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let lines = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { event -> String in
                let time = event.isAllDay
                    ? "All day"
                    : event.startDate.formatted(date: .omitted, time: .shortened)
                return "• \(time): \(event.title ?? "Untitled")"
            }
        return lines.isEmpty ? "Nothing scheduled today." : lines.joined(separator: "\n")
    }

    private func topMemories(context: ModelContext) -> String {
        let memories = searchMemories(query: "today priorities goals plans", context: context, limit: 5)
        guard !memories.isEmpty else { return "" }
        return memories.map { "• \($0.title): \($0.summary)" }.joined(separator: "\n")
    }

    /// Synthesise a short prioritised plan from what the earlier steps gathered.
    private func synthesisePlan(from gathered: [String]) async -> String {
        guard !gathered.isEmpty else { return "" }
        let material = gathered.joined(separator: "\n\n")

        let router = ModelRouter(container: container)
        _ = router.resolve(task: .briefing, estimatedPromptTokens: budget.estimatedTokens(material))

#if canImport(FoundationModels)
        let session = LanguageModelSession(instructions: Self.planInstructions)
        do {
            let response = try await session.respond(
                to: "From this, write a short prioritised plan for today:\n\n\(material)",
                options: GenerationOptions(sampling: .greedy)
            )
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
#else
        return ""
#endif
    }

    private static let planInstructions = """
    You turn a set of notes — calendar, priorities, a brief — into a short, prioritised plan \
    for the day. Three to five plain-text bullet points, most important first. Be concrete \
    and specific to the notes; never pad with generic advice.
    """
}
