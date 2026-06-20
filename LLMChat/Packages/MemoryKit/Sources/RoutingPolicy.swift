import Foundation
import SwiftData

// MARK: - Phase 4 routing policy
//
// The user-owned policy that decides *which model tier* answers a turn (§Phase 4). It
// lives in the synced store like the rest of the person's model: the privacy posture
// ("on-device only", "never third-party") should follow them across devices.
//
// CloudKit mirroring rules apply here exactly as for the memory models (§Phase 3):
//   • no `@Attribute(.unique)`;
//   • every scalar attribute carries an inline default (or is optional);
//   • no relationships needed.
//
// There is conceptually one policy per user. Rather than a unique constraint (forbidden
// under CloudKit), `RoutingPolicy.load(in:)` fetches the first row and creates one on
// first run — the singleton is enforced in code, not the schema.

/// Per-user routing preferences: the privacy lock, which escalations are permitted, the
/// PCC daily ceiling and its running count, and the preferred tier for reasoning-class
/// work. Read by `ModelRouter` before every turn; written from the routing settings UI.
@Model
public final class RoutingPolicy {
    public var id: UUID = UUID()

    /// Hard privacy lock. When true the router never leaves the device, regardless of any
    /// other flag or token pressure — the user's explicit "nothing leaves my phone" switch.
    public var onDeviceOnly: Bool = false

    /// Whether Private Cloud Compute escalation is permitted (Apple-operated, no API keys,
    /// data leaves the device only into Apple's PCC). On by default — it's still Apple.
    public var allowPrivateCloudCompute: Bool = true

    /// Whether a third-party cloud provider may be used. Off by default and opt-in only
    /// (§B): third-party is the one path that leaves Apple's privacy boundary.
    public var allowThirdParty: Bool = false

    /// Opt-in third-party provider identifier (e.g. "claude", "gemini"). Empty = none.
    public var thirdPartyProvider: String = ""

    /// PCC's per-user daily request ceiling. PCC is rate-limited; past this we fall back
    /// to on-device for the rest of the day rather than failing the turn.
    public var pccDailyLimit: Int = 50

    /// PCC requests counted against `pccUsageDate`. Reset when the day rolls over.
    public var pccUsedToday: Int = 0

    /// The calendar day `pccUsedToday` applies to. A different day zeroes the counter.
    public var pccUsageDate: Date = Date.now

    /// Preferred tier for reasoning-class tasks (synthesising a week, multi-step work) —
    /// stored as a raw string for CloudKit safety. Defaults to PCC, the 32K reasoning tier.
    public var reasoningTierRawValue: String = "privateCloudCompute"

    public var updatedAt: Date = Date.now

    public init(
        id: UUID = .init(),
        onDeviceOnly: Bool = false,
        allowPrivateCloudCompute: Bool = true,
        allowThirdParty: Bool = false,
        thirdPartyProvider: String = "",
        pccDailyLimit: Int = 50,
        reasoningTierRawValue: String = "privateCloudCompute"
    ) {
        self.id = id
        self.onDeviceOnly = onDeviceOnly
        self.allowPrivateCloudCompute = allowPrivateCloudCompute
        self.allowThirdParty = allowThirdParty
        self.thirdPartyProvider = thirdPartyProvider
        self.pccDailyLimit = pccDailyLimit
        self.pccUsedToday = 0
        self.pccUsageDate = .now
        self.reasoningTierRawValue = reasoningTierRawValue
        self.updatedAt = .now
    }

    // MARK: - Singleton access

    /// Fetch the single routing policy, creating (and persisting) the default on first run.
    @MainActor
    public static func load(in context: ModelContext) -> RoutingPolicy {
        if let existing = (try? context.fetch(FetchDescriptor<RoutingPolicy>()))?.first {
            return existing
        }
        let policy = RoutingPolicy()
        context.insert(policy)
        try? context.save()
        return policy
    }

    // MARK: - PCC budget metering

    /// Whether a PCC request is still within today's ceiling, rolling the counter over to
    /// a fresh day if needed. Read-only — does not consume budget.
    public func pccBudgetRemaining(now: Date = .now) -> Int {
        if !Calendar.current.isDate(pccUsageDate, inSameDayAs: now) {
            return pccDailyLimit
        }
        return max(0, pccDailyLimit - pccUsedToday)
    }

    /// Record one PCC request against today's budget, resetting the day if it rolled over.
    @MainActor
    public func consumePCC(now: Date = .now, context: ModelContext) {
        if !Calendar.current.isDate(pccUsageDate, inSameDayAs: now) {
            pccUsageDate = now
            pccUsedToday = 0
        }
        pccUsedToday += 1
        updatedAt = now
        try? context.save()
    }
}
