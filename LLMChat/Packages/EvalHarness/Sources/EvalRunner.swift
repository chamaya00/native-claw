import Foundation
import AgentKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Runs an eval suite and produces a report (§Phase 4). Deterministic by construction:
/// every task runs with greedy sampling so a regression is a real quality change, not
/// sampling noise (CLAUDE.md deterministic-options guidance).
///
/// **Tier coverage.** On-device always runs for real. Private Cloud Compute runs for real
/// only when built against the iOS 27 SDK with `-D FM_PCC` (its `PrivateCloudComputeLanguageModel`
/// isn't in the iOS 26 SDK) — then a single run yields a true on-device-vs-PCC quality/latency
/// comparison; otherwise PCC rows are recorded as pending. Third-party is pending until a
/// provider SPM package is added.
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
        // Third-party awaits a provider SPM package, so it's recorded as pending.
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
#if !FM_PCC
        // Private Cloud Compute needs the iOS 27 SDK (`PrivateCloudComputeLanguageModel`),
        // which only compiles under `-D FM_PCC`. Without it, only on-device is measured.
        guard tier != .privateCloudCompute else {
            return EvalResult(
                taskID: task.id,
                tier: tier,
                passed: false,
                latency: 0,
                output: "",
                note: "Private Cloud Compute needs an iOS 27 SDK build (FM_PCC) — not measured."
            )
        }
#endif

#if canImport(FoundationModels)
        let start = Date()
        do {
#if FM_PCC
            let session = LanguageModelSession(model: model(for: tier), instructions: task.instructions)
#else
            let session = LanguageModelSession(instructions: task.instructions)
#endif
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

#if FM_PCC
    /// Map a tier to the concrete model that backs the eval session (WWDC26 `LanguageModel`
    /// protocol). Mirrors `ConversationEngine.model(for:)` so the harness measures exactly
    /// the models the router would route to. Only compiled under `-D FM_PCC` (iOS 27 SDK).
    private func model(for tier: ModelTier) -> any LanguageModel {
        switch tier {
        case .onDevice: return SystemLanguageModel.default
        case .privateCloudCompute: return PrivateCloudComputeLanguageModel()
        case .thirdParty: return SystemLanguageModel.default
        }
    }
#endif
}
