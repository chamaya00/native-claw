import Foundation
import SwiftData

// MARK: - Phase 5 stores: preference learning + routine suggestions
//
// Two on-device personalization signals live here, both user-owned and synced like the
// rest of the person's model:
//   • PreferencePair / UserPref — explicit taste signal from the A/B preference picker.
//   • SuggestedRoutine          — patterns the assistant noticed and proposed, surfaced
//                                 in an in-app inbox (never a push).
//
// Everything here is deliberate and reversible, and nothing notifies the user on its own.
// Approval stays structural: routine suggestions are written `status == "suggested"` and
// only an approved routine ever schedules background work or notifies (§Phase 5 guardrail).

// MARK: - Preference picker (UserPref + PreferencePair)

/// The style axes the preference picker rotates through. Each maps to a concrete pair of
/// generation deltas in `PreferenceLearner` and to a `UserPref` key folded into the
/// persona instructions, so a pick measurably shifts future responses (§Phase 5).
public enum StyleDimension: String, CaseIterable, Sendable {
    case length      // concise ↔ thorough
    case warmth      // matter-of-fact ↔ warm

    /// The `UserPref.key` this dimension persists under (e.g. "style.length").
    public var prefKey: String { "style.\(rawValue)" }
}

/// Record one A/B preference-picker decision: persist the raw taste signal as a
/// `PreferencePair`, and fold the winning style into an **approved** `UserPref` keyed on
/// the dimension. The user picked it explicitly, so it needs no separate approval.
@MainActor
public func recordPreference(
    prompt: String,
    chosen: String,
    rejected: String,
    dimension: StyleDimension,
    chosenValue: String,
    context: ModelContext
) {
    context.insert(PreferencePair(
        prompt: prompt,
        chosenVariant: chosen,
        rejectedVariant: rejected,
        dimension: dimension.rawValue
    ))
    upsertStylePref(key: dimension.prefKey, value: chosenValue, context: context)
    try? context.save()
}

/// Upsert a style preference keyed on `key`, nudging confidence up on repeated agreement.
@MainActor
private func upsertStylePref(key: String, value: String, context: ModelContext) {
    let descriptor = FetchDescriptor<UserPref>(predicate: #Predicate { $0.key == key })
    if let existing = (try? context.fetch(descriptor))?.first {
        existing.value = value
        existing.confidence = min(existing.confidence + 0.15, 1.0)
        existing.isUserApproved = true
        existing.updatedAt = .now
    } else {
        context.insert(UserPref(key: key, value: value, confidence: 0.6, isUserApproved: true))
    }
}

/// The approved style preferences, for folding into the persona instructions each session.
/// `hasPrefix` isn't expressible in `#Predicate`, so the style filter runs in memory.
@MainActor
public func approvedStylePrefs(context: ModelContext) -> [UserPref] {
    let descriptor = FetchDescriptor<UserPref>(predicate: #Predicate { $0.isUserApproved == true })
    let all = (try? context.fetch(descriptor)) ?? []
    return all.filter { $0.key.hasPrefix("style.") }
}

// MARK: - Routine suggestions (SuggestedRoutine inbox)

/// The lifecycle of a suggested routine. Plain strings on the model for CloudKit safety;
/// this enum is the typed view the app reasons with.
public enum RoutineStatus: String, Sendable {
    case suggested      // proposed by the assistant, waiting in the in-app inbox
    case approved       // user accepted — may schedule background work and notify
    case dismissed      // user rejected — kept as a negative signal, never re-proposed
}

/// Routines proposed but not yet acted on — the in-app inbox (never a push). Filtered in
/// memory since `status` is a free string.
@MainActor
public func pendingRoutineSuggestions(context: ModelContext) -> [SuggestedRoutine] {
    let descriptor = FetchDescriptor<SuggestedRoutine>(
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    let all = (try? context.fetch(descriptor)) ?? []
    return all.filter { $0.status == RoutineStatus.suggested.rawValue }
}

/// The approved routines — the set that may schedule background briefings and notify.
@MainActor
public func approvedRoutines(context: ModelContext) -> [SuggestedRoutine] {
    let all = (try? context.fetch(FetchDescriptor<SuggestedRoutine>())) ?? []
    return all.filter { $0.status == RoutineStatus.approved.rawValue }
}

/// Approve a suggested routine. Scheduling/notification permission is handled by the caller
/// (`ProactivityScheduler`) so MemoryKit stays free of BackgroundTasks/UserNotifications.
@MainActor
public func approveRoutine(_ routine: SuggestedRoutine, context: ModelContext) {
    routine.status = RoutineStatus.approved.rawValue
    try? context.save()
}

/// Dismiss a suggestion. The row is kept (not deleted) as a negative signal so the
/// suggester won't re-propose the same routine (§Phase 5: dismissals suppress similar).
@MainActor
public func dismissRoutine(_ routine: SuggestedRoutine, context: ModelContext) {
    routine.status = RoutineStatus.dismissed.rawValue
    try? context.save()
}

/// Edit a routine's title/schedule before or after approval (routines stay editable from
/// the inbox, per the guardrail).
@MainActor
public func updateRoutine(
    _ routine: SuggestedRoutine,
    title: String,
    scheduleHint: String?,
    context: ModelContext
) {
    routine.title = title
    routine.scheduleHint = (scheduleHint?.isEmpty ?? true) ? nil : scheduleHint
    try? context.save()
}

/// Pause an approved routine by returning it to the inbox (dropping it from the scheduled
/// set without losing it). Re-approving re-arms scheduling.
@MainActor
public func pauseRoutine(_ routine: SuggestedRoutine, context: ModelContext) {
    routine.status = RoutineStatus.suggested.rawValue
    try? context.save()
}
