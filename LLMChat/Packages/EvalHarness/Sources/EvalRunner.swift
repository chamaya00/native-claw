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
/// bind. On-device and Private Cloud Compute both run for real (the WWDC26 `LanguageModel`
/// protocol — `SystemLanguageModel.default` and `PrivateCloudComputeLanguageModel`), so a
/// single run yields a true on-device-vs-PCC quality/latency comparison. Third-party is
/// recorded as pending until a provider SPM package is added.
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
        // On-device and PCC have real model bindings; third-party awaits a provider SPM
        // package, so it's recorded as pending (mirrors ModelRouter's binding seam).
        guard tier != .thirdParty else {
            return EvalResult(
                taskID: task.id,
                tier: tier,
                passed: false,
                latency: 0,
                output: "",
                note: "\(tier.displayName) binding is pending — add a provider package."
            )
        }

#if canImport(FoundationModels)
        let start = Date()
        do {
            let session = LanguageModelSession(model: model(for: tier), instructions: task.instructions)
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

#if canImport(FoundationModels)
    /// Map a tier to the concrete model that backs the eval session (WWDC26 `LanguageModel`
    /// protocol). Mirrors `ConversationEngine.model(for:)` so the harness measures exactly
    /// the models the router would route to.
    private func model(for tier: ModelTier) -> any LanguageModel {
        switch tier {
        case .onDevice: return SystemLanguageModel.default
        case .privateCloudCompute: return PrivateCloudComputeLanguageModel()
        case .thirdParty: return SystemLanguageModel.default
        }
    }
#endif
}
