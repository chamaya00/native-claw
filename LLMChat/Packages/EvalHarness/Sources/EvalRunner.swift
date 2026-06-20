import Foundation
import AgentKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Runs an eval suite and produces a report (§Phase 4). Deterministic by construction:
/// every task runs with greedy sampling so a regression is a real quality change, not
/// sampling noise (CLAUDE.md deterministic-options guidance).
///
/// **Tier coverage.** The runner executes whichever tiers the current build can actually
/// bind. On-device runs for real today; the cloud tiers are recorded as skipped with the
/// same binding note the `ModelRouter` reports, so the report makes the on-device/PCC
/// boundary explicit the moment that binding lands — without pretending a PCC number
/// exists when it doesn't.
@MainActor
public struct EvalRunner {

    public init() {}

    /// Run the suite across the requested tiers. Defaults to the suite's natural tier set
    /// (on-device, plus PCC marked pending) so a single call yields a complete report.
    public func run(
        suite: [EvalTask] = AssistantEvalSuite.all,
        tiers: [ModelTier] = [.onDevice, .privateCloudCompute]
    ) async -> EvalReport {
        var results: [EvalResult] = []
        for tier in tiers {
            for task in suite {
                results.append(await runOne(task, on: tier))
            }
        }
        return EvalReport(results: results)
    }

    private func runOne(_ task: EvalTask, on tier: ModelTier) async -> EvalResult {
        // Only the on-device tier has a verified model binding in this build; cloud tiers
        // are recorded as pending (mirrors ModelRouter's binding seam).
        guard tier == .onDevice else {
            return EvalResult(
                taskID: task.id,
                tier: tier,
                passed: false,
                latency: 0,
                output: "",
                note: "\(tier.displayName) binding is pending device provisioning — not yet measured."
            )
        }

#if canImport(FoundationModels)
        let start = Date()
        do {
            let session = LanguageModelSession(instructions: task.instructions)
            let output = try await session.respond(
                to: task.prompt,
                options: GenerationOptions(sampling: .greedy)
            ).content
            let latency = Date().timeIntervalSince(start)
            return EvalResult(
                taskID: task.id,
                tier: tier,
                passed: task.grade(output),
                latency: latency,
                output: output,
                note: nil
            )
        } catch {
            return EvalResult(
                taskID: task.id,
                tier: tier,
                passed: false,
                latency: Date().timeIntervalSince(start),
                output: "",
                note: error.localizedDescription
            )
        }
#else
        return EvalResult(
            taskID: task.id,
            tier: tier,
            passed: false,
            latency: 0,
            output: "",
            note: "FoundationModels unavailable in this build."
        )
#endif
    }
}
