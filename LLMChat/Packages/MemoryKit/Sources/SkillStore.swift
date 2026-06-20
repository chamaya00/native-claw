import Foundation
import SwiftData

// MARK: - Phase 6 store: declarative skills (reusable, named routines)
//
// A `Skill` is a reusable routine the assistant assembles from things the user repeats —
// "my Monday review", "my travel prep". It is a *declarative* composition of named
// actions (`SkillCatalog`), never generated code (App Review §2.5.2), and it follows the
// same propose-then-approve lifecycle as the Phase-5 routine inbox: proposed → approved /
// dismissed, with dismissals kept as a durable negative signal.
//
// This file is the pure SwiftData layer (no FoundationModels, no AppIntents) so it stays
// unit-testable in isolation, mirroring `ProactivityStore`. Suggestion (a model pass),
// execution (`SkillRunner`), and system exposure (App Intents) live in `SkillsKit`.

/// The lifecycle of a skill. Plain strings on the model for CloudKit safety; this enum is
/// the typed view the app reasons with — the same pattern as `RoutineStatus`.
public enum SkillStatus: String, Sendable {
    case suggested      // proposed by the assistant, waiting in the skills inbox
    case approved       // user accepted — runs and is exposed to Siri/Shortcuts
    case dismissed      // user rejected — kept as a negative signal, never re-proposed
}

@MainActor
public enum SkillStore {

    // MARK: - Queries

    /// Skills proposed but not yet acted on — the in-app inbox. Filtered in memory since
    /// `status` is a free string for CloudKit safety.
    public static func suggested(context: ModelContext) -> [Skill] {
        all(context: context).filter { $0.status == SkillStatus.suggested.rawValue }
    }

    /// The approved skills — the set that may run and is exposed to the system.
    public static func approved(context: ModelContext) -> [Skill] {
        all(context: context).filter { $0.status == SkillStatus.approved.rawValue }
    }

    /// Every skill, newest first.
    public static func all(context: ModelContext) -> [Skill] {
        let descriptor = FetchDescriptor<Skill>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Every known skill name — suggested, approved, *or dismissed* — lowercased, so the
    /// suggester can dedupe against dismissals and never re-propose a rejected skill.
    public static func knownNames(context: ModelContext) -> Set<String> {
        Set(all(context: context).map { $0.name.lowercased() })
    }

    // MARK: - Lifecycle

    /// Approve a suggested skill: it becomes runnable and is exposed to the system. Keeps
    /// `isUserApproved` in lockstep so existing approval predicates keep working.
    public static func approve(_ skill: Skill, context: ModelContext) {
        skill.status = SkillStatus.approved.rawValue
        skill.isUserApproved = true
        skill.updatedAt = .now
        try? context.save()
    }

    /// Dismiss a skill. The row is kept (not deleted) as a negative signal so the suggester
    /// won't re-propose it (mirrors the Phase-5 dismissal contract).
    public static func dismiss(_ skill: Skill, context: ModelContext) {
        skill.status = SkillStatus.dismissed.rawValue
        skill.isUserApproved = false
        skill.updatedAt = .now
        try? context.save()
    }

    /// Edit a skill's name/summary/recipe (skills stay editable from the inbox).
    public static func update(
        _ skill: Skill,
        name: String,
        summary: String,
        recipe: [String]? = nil,
        context: ModelContext
    ) {
        skill.name = name
        skill.summary = summary
        if let recipe { skill.intentRecipe = recipe }
        skill.updatedAt = .now
        try? context.save()
    }

    // MARK: - Self-improvement (approval-gated)

    /// Record an assistant-proposed revision (a revised summary). Held on the skill until the
    /// user approves it — revisions are **never** auto-applied (§Phase 6 guardrail).
    public static func proposeRevision(_ text: String, for skill: Skill, context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != skill.summary else { return }
        skill.proposedRevision = trimmed
        try? context.save()
    }

    /// Apply a pending proposed revision (user approved it) and clear it.
    public static func acceptRevision(for skill: Skill, context: ModelContext) {
        guard let revision = skill.proposedRevision else { return }
        skill.summary = revision
        skill.proposedRevision = nil
        skill.updatedAt = .now
        try? context.save()
    }

    /// Reject a pending proposed revision without applying it.
    public static func rejectRevision(for skill: Skill, context: ModelContext) {
        skill.proposedRevision = nil
        try? context.save()
    }

    // MARK: - Run tracking

    /// Record the outcome of one run, feeding `successRate` (the signal self-improvement
    /// reasons from). Best-effort: never throws into a run path.
    public static func recordRun(_ skill: Skill, succeeded: Bool, context: ModelContext) {
        skill.runCount += 1
        if succeeded { skill.successCount += 1 }
        skill.lastRunAt = .now
        try? context.save()
    }
}
