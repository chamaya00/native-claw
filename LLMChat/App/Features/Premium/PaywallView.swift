import SwiftUI
import AgentKit

#if canImport(StoreKit)
import StoreKit
#endif

/// The premium paywall (§Phase 8). Sits exactly at the metered cloud boundary: the free tier is
/// fully usable on-device, and premium unlocks the third-party cloud reasoning tier (§Phase 4)
/// plus richer proactivity. StoreKit 2 is the only native subscription path; when products aren't
/// configured (CI, fresh sandbox) the view degrades to a clear "unavailable" state.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private let store = PremiumStore.shared

    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    benefits
                    productButtons
                    restoreButton
                    fineprint
                }
                .padding(20)
            }
            .navigationTitle("Claw Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { if !store.isSubscribed { await store.start() } }
            .onChange(of: store.isSubscribed) { _, subscribed in
                if subscribed { dismiss() }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "cloud.bolt.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            Text("Cloud-grade reasoning, on demand")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Everything stays free and private on-device. Premium adds an opt-in cloud tier for the hardest, multi-step work.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow("brain.head.profile", "Cloud reasoning tier", "Route genuinely hard tasks to a large-context cloud model — you choose when, per the routing policy.")
            benefitRow("sparkles", "Richer proactivity", "More capable briefings and suggestions built from your on-device memory.")
            benefitRow("lock.shield", "Privacy preserved", "On-device and Private Cloud Compute stay free. Cloud is opt-in and always shown in the transparency chip.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func benefitRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var productButtons: some View {
#if canImport(StoreKit)
        if store.isLoading {
            ProgressView().padding(.vertical, 8)
        } else if store.products.isEmpty {
            Text("Subscription options aren't available right now. Please try again later.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        } else {
            ForEach(store.products, id: \.id) { product in
                Button {
                    Task { await buy(product) }
                } label: {
                    HStack {
                        Text(product.displayName.isEmpty ? "Premium" : product.displayName)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(product.displayPrice)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isWorking)
            }
        }
#else
        Text("Subscriptions require StoreKit.")
            .font(.footnote)
            .foregroundStyle(.secondary)
#endif
        if let error = store.purchaseError {
            Text(error).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
        }
    }

    private var restoreButton: some View {
        Button("Restore purchases") {
            Task { isWorking = true; await store.restore(); isWorking = false }
        }
        .font(.subheadline)
        .disabled(isWorking)
    }

    private var fineprint: some View {
        Text("Subscriptions renew automatically until cancelled. Manage or cancel anytime in Settings. The free tier remains fully functional on-device.")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .multilineTextAlignment(.center)
    }

#if canImport(StoreKit)
    private func buy(_ product: Product) async {
        isWorking = true
        defer { isWorking = false }
        _ = await store.purchase(product)
    }
#endif
}
