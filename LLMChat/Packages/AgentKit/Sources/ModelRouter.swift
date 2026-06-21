import Foundation
import SwiftData
import Observation
import MemoryKit

/// The outcome of routing one turn (§Phase 4). Separates *intent* from *reality*:
///   • `policyTier` — what the user's `RoutingPolicy`, the task kind, and the token
///     pressure selected. This is the real, fully-tested decision.
///   • `boundTier`  — the tier that actually backs the session in *this* build. On-device
///     and Private Cloud Compute are real bindings (the WWDC26 `LanguageModel` protocol);
///     the third-party tier still awaits a provider SPM package and degrades to on-device.
/// `degraded` is true when reality couldn't meet intent, and `reason` explains why — both
/// surface in the routing settings so the user always knows where their data went.
public struct RoutingResolution: Sendable, Equatable {
    public let task: TaskKind
    public let policyTier: ModelTier
    public let boundTier: ModelTier
    public let degraded: Bool
    public let reason: String

    /// The window the engine should budget against — always the *bound* tier's, since
    /// that's the model that will actually run.
    public var contextSize: Int { boundTier.contextSize }
}

/// Decides which model tier answers a turn and surfaces it for transparency (§Phase 4).
///
/// Hidden behind this one type is the entire escalation policy: everyday chat stays
/// on-device (instant, free, private); work that needs reasoning or won't fit the 4K
/// window escalates to PCC by policy; third-party is opt-in only. The call site only asks
/// "route this task" — it never names a model — so the rest of the app is untouched when
/// tiers change (the reason the plan defers `ModelRouter` to the phase where it earns its
/// keep, §deviation 4).
///
/// **Binding seam.** Resolving *which* tier should run is real and tested here. *Binding*
/// a tier to a concrete FoundationModels model happens in `ConversationEngine` via the
/// WWDC26 `LanguageModel` protocol (`SystemLanguageModel.default` ↔ `PrivateCloudComputeLanguageModel`).
/// On-device and PCC are real bindings now; only the third-party tier still awaits a
/// provider SPM package, so `bind(_:)` degrades *that* tier to on-device and flags it.
/// The policy, metering, and transparency around every tier already ship.
@Observable
@MainActor
public final class ModelRouter {
    private let container: ModelContainer

    /// The most recent routing decision, for the transparency chip and settings screen.
    public private(set) var lastResolution: RoutingResolution?

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Resolution

    /// Resolve the tier for a turn given the task kind and an estimate of how many tokens
    /// the prompt needs. Pure policy: loads `RoutingPolicy`, applies the privacy lock,
    /// permission flags, token pressure, and PCC daily budget, then binds to a model the
    /// current build can actually run.
    public func resolve(task: TaskKind, estimatedPromptTokens: Int) -> RoutingResolution {
        let context = ModelContext(container)
        let policy = RoutingPolicy.load(in: context)

        // 1. Desired tier from the task kind.
        var desired: ModelTier = task.prefersReasoningTier
            ? (ModelTier(rawValue: policy.reasoningTierRawValue) ?? .privateCloudCompute)
            : .onDevice

        // 2. Escalate if the prompt simply won't fit the on-device window. The 4K ceiling
        //    is the whole reason PCC exists (§Phase 4 rationale).
        let onDeviceRoom = ModelTier.onDevice.contextSize - ContextBudget().responseHeadroom
        var escalatedForSize = false
        if estimatedPromptTokens > onDeviceRoom, desired == .onDevice {
            desired = .privateCloudCompute
            escalatedForSize = true
        }

        // 3. Apply policy → the tier that *should* run.
        let (policyTier, reason) = applyPolicy(
            desired: desired,
            escalatedForSize: escalatedForSize,
            policy: policy
        )

        // 4. Bind to a model this build can instantiate.
        let (boundTier, bindNote) = bind(policyTier)
        let resolution = RoutingResolution(
            task: task,
            policyTier: policyTier,
            boundTier: boundTier,
            degraded: boundTier != policyTier,
            reason: bindNote ?? reason
        )

        // Meter PCC only when a PCC call is actually about to be made.
        if boundTier == .privateCloudCompute {
            policy.consumePCC(context: context)
        }

        lastResolution = resolution
        return resolution
    }

    /// Clamp the desired tier to what the policy permits, narrating the decision.
    private func applyPolicy(
        desired: ModelTier,
        escalatedForSize: Bool,
        policy: RoutingPolicy
    ) -> (ModelTier, String) {
        // Privacy lock wins over everything.
        if policy.onDeviceOnly {
            return (.onDevice, "On-device only is on — nothing leaves this device.")
        }

        switch desired {
        case .onDevice:
            return (.onDevice, "Handled on-device.")

        case .thirdParty:
            // Third-party cloud is the premium tier (§Phase 8): paid = cloud. Without an active
            // subscription it's never used, even if opted in — the free tier stays on-device/PCC.
            if !PremiumEntitlement.isActive {
                return demoteFromCloud(policy: policy, blocked: "Third-party cloud is a premium feature")
            }
            if policy.allowThirdParty, !policy.thirdPartyProvider.isEmpty {
                return (.thirdParty, "Routed to \(policy.thirdPartyProvider) (premium cloud).")
            }
            // Third-party not permitted → try PCC, else on-device.
            return demoteFromCloud(policy: policy, blocked: "Third-party cloud is off")

        case .privateCloudCompute:
            if !policy.allowPrivateCloudCompute {
                return (.onDevice, "Private Cloud Compute is off — kept on-device.")
            }
            if policy.pccBudgetRemaining() <= 0 {
                return (.onDevice, "Private Cloud Compute daily limit reached — kept on-device.")
            }
            let why = escalatedForSize
                ? "Escalated to Private Cloud Compute — the request is too large for the on-device window."
                : "Routed to Private Cloud Compute for reasoning."
            return (.privateCloudCompute, why)
        }
    }

    private func demoteFromCloud(policy: RoutingPolicy, blocked: String) -> (ModelTier, String) {
        if policy.allowPrivateCloudCompute, policy.pccBudgetRemaining() > 0 {
            return (.privateCloudCompute, "\(blocked) — used Private Cloud Compute instead.")
        }
        return (.onDevice, "\(blocked) — kept on-device.")
    }

    /// Bind a policy tier to a model the current build can run. On-device and Private Cloud
    /// Compute are real bindings (the engine instantiates `SystemLanguageModel.default` and
    /// `PrivateCloudComputeLanguageModel` respectively). Third-party still awaits a provider
    /// SPM package, so it degrades to on-device and flags the degradation.
    private func bind(_ tier: ModelTier) -> (ModelTier, String?) {
        switch tier {
        case .onDevice:
            return (.onDevice, nil)
        case .privateCloudCompute:
            return (.privateCloudCompute, nil)
        case .thirdParty:
            return (.onDevice, "Third-party provider binding is pending; this turn ran on-device.")
        }
    }
}
