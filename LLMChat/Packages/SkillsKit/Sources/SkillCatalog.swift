import Foundation

/// The fixed vocabulary of declarative actions a `Skill` recipe can compose (§Phase 6).
///
/// This is the heart of the App-Store-legal "self-improvement" loop: a skill is an ordered
/// list of these named actions — a *recipe*, not generated code (App Review §2.5.2). Every
/// action here is **read-only or already user-approved**, so running a skill can never slip
/// an unapproved mutation past the `ApprovalGate`. Adding a new capability is a matter of
/// adding a case and teaching `SkillRunner` to perform it; the recipe vocabulary stays a
/// closed, auditable set.
///
/// `rawValue` is the stable identifier persisted in `Skill.intentRecipe`, so the strings
/// here are a schema contract — rename with care.
public enum SkillAction: String, Sendable, CaseIterable, Identifiable {
    case checkCalendar      // read today's events (read-only)
    case reviewMemory       // surface the user's top durable memories (read-only)
    case dailyBrief         // generate the proactive daily brief (on-device synthesis)
    case planDay            // synthesise a short prioritised plan from the above

    public var id: String { rawValue }

    /// Short imperative label for the skill editor and run output.
    public var displayName: String {
        switch self {
        case .checkCalendar: return "Check today's calendar"
        case .reviewMemory:  return "Review what I care about"
        case .dailyBrief:    return "Generate my daily brief"
        case .planDay:       return "Draft a prioritised plan"
        }
    }

    public var systemImage: String {
        switch self {
        case .checkCalendar: return "calendar"
        case .reviewMemory:  return "brain"
        case .dailyBrief:    return "sun.max"
        case .planDay:       return "list.bullet.clipboard"
        }
    }

    /// Decode a persisted recipe into known actions, dropping any unknown identifiers so a
    /// recipe written by a newer build degrades gracefully rather than failing to run.
    public static func recipe(from identifiers: [String]) -> [SkillAction] {
        identifiers.compactMap { SkillAction(rawValue: $0) }
    }

    /// A sensible default recipe for a freshly-suggested skill, so an approved skill always
    /// has something concrete to run even before the user edits it.
    public static var defaultRecipe: [String] {
        [SkillAction.checkCalendar.rawValue,
         SkillAction.reviewMemory.rawValue,
         SkillAction.planDay.rawValue]
    }
}
