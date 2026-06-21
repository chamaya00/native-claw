import Foundation
import SwiftData

// MARK: - Privacy-respecting north-star metrics (§Phase 8)
//
// The PRD's north star is personalization depth × retention. To steer it we track a handful
// of **aggregate counters** — activation, preference-picker participation, suggestion approval,
// routine pausing — and nothing else. There is **no analytics SDK and no network call**: counts
// live in the same on-device/private-CloudKit store as the rest of the person's data (§B: no
// personal data leaves the device). They're aggregate tallies, never event logs with content, so
// they reveal usage *shape* without exposing what was said or done.

/// One named, monotonic counter. CloudKit-safe like every other model (all defaulted, no
/// `@Attribute(.unique)`): "one row per key" is enforced in code by `Metrics`, not the schema.
@Model
public final class UsageCounter {
    public var key: String = ""
    public var count: Int = 0
    public var updatedAt: Date = .now

    public init(key: String = "", count: Int = 0) {
        self.key = key
        self.count = count
        self.updatedAt = .now
    }
}

/// The signals worth counting for the north star. Deliberately small and content-free.
public enum UsageMetric: String, CaseIterable, Sendable {
    case activated            // reached the assistant for the first time (onboarding complete)
    case magicMomentShown     // saw a personalized first observation
    case preferenceOffered    // an A/B style picker was surfaced
    case preferenceAnswered   // the user actually picked a variant
    case suggestionApproved   // approved a suggested routine
    case routinePaused        // paused an approved routine (a churn-risk signal)

    public var label: String {
        switch self {
        case .activated: return "Activated"
        case .magicMomentShown: return "First impression shown"
        case .preferenceOffered: return "Style pickers offered"
        case .preferenceAnswered: return "Style pickers answered"
        case .suggestionApproved: return "Routines approved"
        case .routinePaused: return "Routines paused"
        }
    }
}

/// Increment and read the aggregate counters. All on the main actor against the shared store.
public enum Metrics {
    /// Bump a counter by one, creating its row on first use. Best-effort; never throws into
    /// the call site (metrics must not break a feature).
    @MainActor
    public static func increment(_ metric: UsageMetric, in context: ModelContext) {
        let key = metric.rawValue
        let descriptor = FetchDescriptor<UsageCounter>(predicate: #Predicate { $0.key == key })
        if let counter = (try? context.fetch(descriptor))?.first {
            counter.count += 1
            counter.updatedAt = .now
        } else {
            context.insert(UsageCounter(key: key, count: 1))
        }
        try? context.save()
    }

    /// Increment a metric at most once for the whole store (e.g. activation). Returns true if
    /// this call was the one that recorded it.
    @MainActor
    @discardableResult
    public static func recordOnce(_ metric: UsageMetric, in context: ModelContext) -> Bool {
        guard count(metric, in: context) == 0 else { return false }
        increment(metric, in: context)
        return true
    }

    @MainActor
    public static func count(_ metric: UsageMetric, in context: ModelContext) -> Int {
        let key = metric.rawValue
        let descriptor = FetchDescriptor<UsageCounter>(predicate: #Predicate { $0.key == key })
        return (try? context.fetch(descriptor))?.first?.count ?? 0
    }
}
