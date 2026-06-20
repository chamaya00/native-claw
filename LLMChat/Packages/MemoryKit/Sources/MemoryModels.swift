import Foundation
import SwiftData

// MARK: - Phase 3 memory models (the durable, user-owned model of the person)
//
// These are the long-term memory types from the plan (§Phase 3 / PRD §9). They ship
// now — even though Phases 5–6 are the first heavy consumers — because the CloudKit
// mirroring rules have to be baked into the schema from the first synced commit;
// retrofitting them onto a shipped store is a migration nightmare (§B).
//
// CloudKit mirroring rules, enforced on every type here:
//   • no `@Attribute(.unique)` anywhere;
//   • every stored property is optional or defaulted via `init`;
//   • relationships are optional and declare an explicit inverse.
//
// `MemoryNote` (in Models.swift) is the realised "MemoryFact": the assistant's durable
// recollection unit, already wired through curation, approval, retrieval, and the
// browser. The types below cover the rest of PRD §9 — learned preferences, taste
// signal, proposed routines, capability recipes, and streamline grants.

/// A single learned preference ("prefers metric units", "writes in lowercase"). Distinct
/// from a `MemoryNote` fact: prefs shape *how* the assistant responds and fold into the
/// persona instructions, where facts are *what* it knows.
@Model
public final class UserPref {
    public var id: UUID = UUID()
    /// Stable preference key, e.g. "tone", "units", "responseLength".
    public var key: String = ""
    public var value: String = ""
    public var confidence: Float = 0.5
    public var isUserApproved: Bool = false
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = .init(),
        key: String = "",
        value: String = "",
        confidence: Float = 0.5,
        isUserApproved: Bool = false
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.confidence = confidence
        self.isUserApproved = isUserApproved
        self.updatedAt = .now
    }
}

/// One A/B preference-picker decision (Phase 5). Stored as explicit, on-device taste
/// signal — and, later, adapter-training data — without anything leaving the device.
@Model
public final class PreferencePair {
    public var id: UUID = UUID()
    public var prompt: String = ""
    public var chosenVariant: String = ""
    public var rejectedVariant: String = ""
    /// The style axis the variants differed on, e.g. "length", "warmth".
    public var dimension: String = ""
    public var createdAt: Date = Date.now

    public init(
        id: UUID = .init(),
        prompt: String = "",
        chosenVariant: String = "",
        rejectedVariant: String = "",
        dimension: String = ""
    ) {
        self.id = id
        self.prompt = prompt
        self.chosenVariant = chosenVariant
        self.rejectedVariant = rejectedVariant
        self.dimension = dimension
        self.createdAt = .now
    }
}

/// A pattern the assistant noticed and proposed turning into a routine (Phase 5). Surfaced
/// in an in-app inbox — never a push — and only notifies once `status == approved`.
@Model
public final class SuggestedRoutine {
    public var id: UUID = UUID()
    public var title: String = ""
    public var rationale: String = ""
    /// "suggested" | "approved" | "dismissed". Plain string for CloudKit safety.
    public var status: String = "suggested"
    /// Natural-language schedule hint, e.g. "weekdays 8am". Concretised at registration.
    public var scheduleHint: String?
    public var createdAt: Date = Date.now

    public init(
        id: UUID = .init(),
        title: String = "",
        rationale: String = "",
        status: String = "suggested",
        scheduleHint: String? = nil
    ) {
        self.id = id
        self.title = title
        self.rationale = rationale
        self.status = status
        self.scheduleHint = scheduleHint
        self.createdAt = .now
    }
}

/// A reusable, named routine assembled from repeated actions (Phase 6). Persisted as a
/// *declarative* recipe of App Intent identifiers — never generated code (App Review §2.5.2).
///
/// The lifecycle mirrors the Phase-5 `SuggestedRoutine` inbox: a skill is proposed
/// (`status == "suggested"`), the user approves/edits/dismisses it, and only an
/// **approved** skill runs or is exposed to Siri/Shortcuts. `isUserApproved` is kept in
/// lockstep with `status == "approved"` so existing approval predicates keep working.
@Model
public final class Skill {
    public var id: UUID = UUID()
    public var name: String = ""
    public var summary: String = ""
    /// One sentence on why the assistant proposed this skill, grounded in the user's pattern.
    public var rationale: String = ""
    /// Ordered declarative action identifiers composing the routine (from `SkillCatalog`).
    /// Declarative only — never code (App Review §2.5.2).
    public var intentRecipe: [String] = []
    /// "suggested" | "approved" | "dismissed". Plain string for CloudKit safety; the typed
    /// `SkillStatus` view lives in `SkillStore`. Dismissed rows are kept as a durable
    /// negative signal so the suggester never re-proposes them.
    public var status: String = "suggested"
    /// A pending self-improvement the assistant proposed (a revised summary/recipe), held
    /// here until the user approves it — revisions are approval-gated, never auto-applied.
    public var proposedRevision: String?
    public var runCount: Int = 0
    public var successCount: Int = 0
    public var isUserApproved: Bool = false
    public var lastRunAt: Date?
    public var createdAt: Date = Date.now
    public var updatedAt: Date = Date.now

    public init(
        id: UUID = .init(),
        name: String = "",
        summary: String = "",
        rationale: String = "",
        intentRecipe: [String] = [],
        status: String = "suggested",
        proposedRevision: String? = nil,
        runCount: Int = 0,
        successCount: Int = 0,
        isUserApproved: Bool = false,
        lastRunAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.rationale = rationale
        self.intentRecipe = intentRecipe
        self.status = status
        self.proposedRevision = proposedRevision
        self.runCount = runCount
        self.successCount = successCount
        self.isUserApproved = isUserApproved
        self.lastRunAt = lastRunAt
        self.createdAt = .now
        self.updatedAt = .now
    }

    /// Share of runs that succeeded, in `0...1`. Zero when never run.
    public var successRate: Double {
        guard runCount > 0 else { return 0 }
        return Double(successCount) / Double(runCount)
    }
}

/// A user-granted permission for the assistant to act in a given scope without re-asking
/// each time (PRD §9 "streamline grants"). Always defaults to *not* granted.
@Model
public final class StreamlineGrant {
    public var id: UUID = UUID()
    /// The action scope this grant covers, e.g. "createReminder", "morningBriefing".
    public var scope: String = ""
    public var isGranted: Bool = false
    public var grantedAt: Date?

    public init(
        id: UUID = .init(),
        scope: String = "",
        isGranted: Bool = false,
        grantedAt: Date? = nil
    ) {
        self.id = id
        self.scope = scope
        self.isGranted = isGranted
        self.grantedAt = grantedAt
    }
}
