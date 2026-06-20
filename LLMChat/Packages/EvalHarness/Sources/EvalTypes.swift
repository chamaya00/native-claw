import Foundation
import AgentKit

// MARK: - Evaluations harness (§Phase 4)
//
// A small on-device model with a hard 4K window must be *measured*, not guessed at: the
// plan makes this non-negotiable (§A.5, §E). This harness converts "which tier should
// run this task?" from a vibe into data — it runs representative assistant tasks, grades
// the output, and reports pass-rate and latency per tier.
//
// **Grader seam.** Apple's Evaluations framework (the WWDC26 surface §Phase 4 names)
// can't be compile-verified without a device, so grading here is a deterministic
// keyword/structure check — fully runnable today. `EvalTask.grade` is the single seam to
// swap in the Evaluations framework with an LLM grader once it can be verified on device.

/// One representative assistant task with a deterministic pass condition.
public struct EvalTask: Sendable, Identifiable {
    public let id: String
    /// The kind of work this task represents — lets a report group results the way the
    /// router groups routing decisions.
    public let kind: TaskKind
    /// Session instructions used for the eval (kept compact, like production).
    public let instructions: String
    /// The user prompt under test.
    public let prompt: String
    /// All of these substrings must appear in the output (case-insensitive) to pass. This
    /// is the deterministic stand-in for an LLM grader (see file header).
    public let mustContain: [String]
    /// Why this task is in the suite — the on-device behaviour it pins down.
    public let rationale: String

    public init(
        id: String,
        kind: TaskKind,
        instructions: String,
        prompt: String,
        mustContain: [String],
        rationale: String
    ) {
        self.id = id
        self.kind = kind
        self.instructions = instructions
        self.prompt = prompt
        self.mustContain = mustContain
        self.rationale = rationale
    }

    /// Deterministic grade: pass iff every required substring is present.
    public func grade(_ output: String) -> Bool {
        let haystack = output.lowercased()
        return mustContain.allSatisfy { haystack.contains($0.lowercased()) }
    }
}

/// The outcome of running one task on one tier.
public struct EvalResult: Sendable, Identifiable {
    public var id: String { "\(taskID)#\(tier.rawValue)" }
    public let taskID: String
    public let tier: ModelTier
    public let passed: Bool
    public let latency: TimeInterval
    public let output: String
    /// Non-nil when the task was skipped or errored (e.g. tier binding unavailable).
    public let note: String?

    public init(
        taskID: String,
        tier: ModelTier,
        passed: Bool,
        latency: TimeInterval,
        output: String,
        note: String?
    ) {
        self.taskID = taskID
        self.tier = tier
        self.passed = passed
        self.latency = latency
        self.output = output
        self.note = note
    }
}

/// A full run of the suite. Carries the per-task results plus rolled-up pass-rate and
/// latency the routing decisions can be argued from (data, not vibes — §E).
public struct EvalReport: Sendable {
    public let results: [EvalResult]
    public let generatedAt: Date

    public init(results: [EvalResult], generatedAt: Date = .now) {
        self.results = results
        self.generatedAt = generatedAt
    }

    /// Tiers that actually produced results.
    public var tiers: [ModelTier] {
        var seen: [ModelTier] = []
        for r in results where !seen.contains(r.tier) { seen.append(r.tier) }
        return seen
    }

    public func passRate(for tier: ModelTier) -> Double {
        let scored = results.filter { $0.tier == tier && $0.note == nil }
        guard !scored.isEmpty else { return 0 }
        return Double(scored.filter(\.passed).count) / Double(scored.count)
    }

    public func averageLatency(for tier: ModelTier) -> TimeInterval {
        let timed = results.filter { $0.tier == tier && $0.note == nil }
        guard !timed.isEmpty else { return 0 }
        return timed.map(\.latency).reduce(0, +) / Double(timed.count)
    }

    public var passedCount: Int { results.filter { $0.passed && $0.note == nil }.count }
    public var scoredCount: Int { results.filter { $0.note == nil }.count }
}
