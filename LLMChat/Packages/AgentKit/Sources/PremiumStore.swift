import Foundation
import Observation

#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - Premium (StoreKit 2) — paid = cloud (§Phase 8)
//
// The business model is structured around the actual cost curve: on-device inference is free to
// us, so the **free tier stays fully usable on-device-only** and the paywall sits exactly at the
// metered cloud boundary. Premium unlocks the **third-party cloud routing tier** (§Phase 4) — the
// one path that leaves Apple's privacy boundary — plus richer proactivity later. Private Cloud
// Compute stays free because it's still Apple.
//
// StoreKit 2 is the only native subscription path. Products are configured in App Store Connect;
// when they aren't (CI, a fresh sandbox) `products` is simply empty and the paywall degrades to an
// "unavailable" state rather than crashing — the same graceful-fallback discipline as availability.

/// The process-wide premium gate the `ModelRouter` reads synchronously before allowing a
/// third-party route. `PremiumStore` keeps it in step with the live StoreKit entitlement; the
/// router never imports StoreKit, so the policy layer stays UI- and store-free.
public enum PremiumEntitlement {
    @MainActor public private(set) static var isActive: Bool = false

    @MainActor
    public static func set(_ active: Bool) { isActive = active }
}

@MainActor
@Observable
public final class PremiumStore {

    /// App Store Connect product identifiers for the premium subscription group.
    public static let monthlyProductID = "com.charlesamaya.llmchat.premium.monthly"
    public static let yearlyProductID = "com.charlesamaya.llmchat.premium.yearly"
    public static let productIDs = [monthlyProductID, yearlyProductID]

    /// The app's shared store. Owned here so the router gate, the paywall, and settings all
    /// observe one entitlement.
    public static let shared = PremiumStore()

    public private(set) var isSubscribed: Bool = false
    public private(set) var isLoading: Bool = false
    public var purchaseError: String?

#if canImport(StoreKit)
    public private(set) var products: [Product] = []
    private var updatesTask: Task<Void, Never>?
#endif

    public init() {}

    /// Load products, reconcile current entitlements, and begin listening for transaction
    /// updates (renewals, refunds, purchases on other devices). Safe to call once at launch.
    public func start() async {
#if canImport(StoreKit)
        await loadProducts()
        await refreshEntitlements()
        listenForTransactions()
#endif
    }

#if canImport(StoreKit)
    public func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Self.productIDs)
            // Cheapest first so the paywall leads with the lower commitment.
            products = loaded.sorted { $0.price < $1.price }
        } catch {
            purchaseError = "Couldn't load subscription options."
        }
    }

    /// Purchase a product, returning true on a verified success.
    @discardableResult
    public func purchase(_ product: Product) async -> Bool {
        purchaseError = nil
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
                return isSubscribed
            case .userCancelled:
                return false
            case .pending:
                purchaseError = "Your purchase is pending approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            purchaseError = error.localizedDescription
            return false
        }
    }

    /// Restore by re-syncing with the App Store, then re-checking entitlements.
    public func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            purchaseError = "Couldn't restore purchases."
        }
        await refreshEntitlements()
    }

    /// Recompute `isSubscribed` from the current entitlements and mirror it into the gate.
    public func refreshEntitlements() async {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }
            if transaction.productType == .autoRenewable,
               Self.productIDs.contains(transaction.productID),
               transaction.revocationDate == nil {
                if let expiry = transaction.expirationDate {
                    if expiry > .now { active = true }
                } else {
                    active = true
                }
            }
        }
        isSubscribed = active
        PremiumEntitlement.set(active)
    }

    private func listenForTransactions() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { continue }
                if let transaction = try? self.checkVerified(update) {
                    await transaction.finish()
                }
                await self.refreshEntitlements()
            }
        }
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified:
            throw PremiumError.unverified
        }
    }

    enum PremiumError: LocalizedError {
        case unverified
        var errorDescription: String? { "The App Store could not verify this purchase." }
    }
#endif
}
