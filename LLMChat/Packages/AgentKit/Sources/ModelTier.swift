import Foundation

/// The model tiers the router can route a turn to (§Phase 4). Ordered by escalation:
/// on-device is the private, free, instant default; PCC is Apple's reasoning escape
/// hatch for work that doesn't fit the 4K window; third-party is opt-in/premium only.
///
/// The whole point of the `ModelTier` abstraction is that the *call site never changes* —
/// only which tier backs the session does. The raw value is stable for persistence
/// (`RoutingPolicy.reasoningTierRawValue`).
public enum ModelTier: String, Sendable, CaseIterable, Codable {
    case onDevice
    case privateCloudCompute
    case thirdParty

    /// Full name for settings UI.
    public var displayName: String {
        switch self {
        case .onDevice: return "On-device"
        case .privateCloudCompute: return "Private Cloud Compute"
        case .thirdParty: return "Third-party cloud"
        }
    }

    /// Compact label for the per-turn transparency chip under an assistant reply.
    public var shortLabel: String {
        switch self {
        case .onDevice: return "On-device"
        case .privateCloudCompute: return "Private Cloud"
        case .thirdParty: return "Cloud"
        }
    }

    public var systemImage: String {
        switch self {
        case .onDevice: return "iphone"
        case .privateCloudCompute: return "lock.icloud"
        case .thirdParty: return "cloud"
        }
    }

    /// Token window for the tier. The on-device model is a fixed 4K; PCC opens a 32K
    /// window with reasoning (§Phase 4). Third-party is provider-dependent — we assume a
    /// conservative large window. The `ContextBudget` is built from this per routed turn.
    public var contextSize: Int {
        switch self {
        case .onDevice: return 4096
        case .privateCloudCompute: return 32_768
        case .thirdParty: return 32_768
        }
    }

    /// Whether personal data leaves the device for this tier. On-device and PCC keep the
    /// strong privacy claim (PCC is Apple-operated); only third-party crosses that line.
    public var leavesDevice: Bool {
        switch self {
        case .onDevice: return false
        case .privateCloudCompute, .thirdParty: return true
        }
    }
}

/// The kind of work a turn represents. The router maps task kind → a preferred tier so
/// everyday chat stays instant and private while genuinely hard work can escalate — the
/// user never has to pick a model (§Phase 4 product requirement).
public enum TaskKind: String, Sendable {
    case chat            // ordinary conversational turn
    case summarization   // condensing the transcript (ContextBudget)
    case curation        // distilling durable facts (MemoryManager)
    case reasoning       // multi-step synthesis the user explicitly asked for
    case briefing        // proactive digest generation (Phase 5)

    /// The tier this kind prefers *before* policy and budget are applied. Light, private
    /// work stays on-device; reasoning/briefing default to the configured reasoning tier
    /// (resolved by the router from `RoutingPolicy`).
    public var prefersReasoningTier: Bool {
        switch self {
        case .chat, .summarization, .curation: return false
        case .reasoning, .briefing: return true
        }
    }
}
