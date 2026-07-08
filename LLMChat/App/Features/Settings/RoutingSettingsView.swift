import SwiftUI
import SwiftData
import MemoryKit
import AgentKit
import EvalHarness

/// Phase 4 transparency surface: shows where turns are routed, lets the user set the
/// privacy posture (on-device-only, which escalations are allowed), and runs the eval
/// harness on demand. The whole point is that the user never *has* to think about models —
/// but can always see and control where their data goes.
struct RoutingSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var policies: [RoutingPolicy]

    private let engine: ConversationEngine
    private let premium = PremiumStore.shared

    @State private var isRunningEvals = false
    @State private var report: EvalReport?
    @State private var showPaywall = false

    init(engine: ConversationEngine) {
        self.engine = engine
    }

    private var policy: RoutingPolicy? { policies.first }

    var body: some View {
        Form {
            lastRouteSection
            privacySection
            escalationSection
            pccBudgetSection
            premiumSection
            usageSection
            evalSection
        }
        .navigationTitle("Model routing")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { ensurePolicy() }
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: - Where the last turn went (transparency)

    @ViewBuilder
    private var lastRouteSection: some View {
        if let resolution = engine.router.lastResolution {
            Section("Last turn") {
                LabeledContent("Ran on") {
                    Label(resolution.boundTier.shortLabel, systemImage: resolution.boundTier.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                if resolution.degraded {
                    LabeledContent("Requested", value: resolution.policyTier.displayName)
                }
                Text(resolution.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Privacy lock

    private var privacySection: some View {
        Section {
            Toggle("On-device only", isOn: bind(\.onDeviceOnly))
        } header: {
            Text("Privacy")
        } footer: {
            Text("When on, nothing ever leaves this device — no Private Cloud Compute, no third-party cloud — regardless of the settings below.")
        }
    }

    // MARK: - Escalation permissions

    @ViewBuilder
    private var escalationSection: some View {
        if let policy, !policy.onDeviceOnly {
            Section {
                Toggle("Private Cloud Compute", isOn: bind(\.allowPrivateCloudCompute))

                // Third-party cloud is the premium tier (§Phase 8). Without a subscription it's
                // gated behind the paywall and never routed to, even if previously opted in.
                if premium.isSubscribed {
                    Toggle("Third-party cloud", isOn: bind(\.allowThirdParty))
                    if policy.allowThirdParty {
                        TextField("Provider", text: bind(\.thirdPartyProvider))
                            .textInputAutocapitalization(.never)
                    }
                } else {
                    Button { showPaywall = true } label: {
                        HStack {
                            Text("Third-party cloud").foregroundStyle(.primary)
                            Spacer()
                            Label("Premium", systemImage: "crown.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tint)
                        }
                    }
                }

                Picker("Reasoning tasks", selection: reasoningTierBinding) {
                    Text(ModelTier.onDevice.displayName).tag(ModelTier.onDevice)
                    Text(ModelTier.privateCloudCompute.displayName).tag(ModelTier.privateCloudCompute)
                }
            } header: {
                Text("Escalation")
            } footer: {
                Text("Everyday chat always stays on-device. Hard, multi-step work can escalate to the tier you pick here. Third-party cloud is a premium tier and the only path that leaves Apple's privacy boundary, so it's opt-in.")
            }
        }
    }

    // MARK: - PCC budget

    @ViewBuilder
    private var pccBudgetSection: some View {
        if let policy, !policy.onDeviceOnly, policy.allowPrivateCloudCompute {
            Section("Private Cloud Compute budget") {
                LabeledContent("Used today", value: "\(policy.pccUsedToday) / \(policy.pccDailyLimit)")
                Stepper("Daily limit: \(policy.pccDailyLimit)", value: bind(\.pccDailyLimit), in: 0...500, step: 10)
            }
        }
    }

    // MARK: - Premium (Phase 8)

    private var premiumSection: some View {
        Section {
            if premium.isSubscribed {
                Label("Claw Premium active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.tint)
            } else {
                Button {
                    showPaywall = true
                } label: {
                    Label("Unlock cloud reasoning", systemImage: "crown.fill")
                }
            }
        } header: {
            Text("Premium")
        } footer: {
            Text("The free tier is fully usable on-device. Premium adds the opt-in third-party cloud reasoning tier for the hardest work.")
        }
    }

    // MARK: - Usage (Phase 8 north-star signals, on-device only)

    private var usageSection: some View {
        Section {
            ForEach(UsageMetric.allCases, id: \.self) { metric in
                LabeledContent(metric.label, value: "\(Metrics.count(metric, in: modelContext))")
            }
        } header: {
            Text("Your usage")
        } footer: {
            Text("Aggregate counts kept on-device (and in your private iCloud) to help Claw improve — no analytics service, no content, nothing sent anywhere.")
        }
    }

    // MARK: - Evaluations harness

    private var evalSection: some View {
        Section {
            Button {
                Task { await runEvals() }
            } label: {
                if isRunningEvals {
                    HStack { ProgressView(); Text("Running evals…") }
                } else {
                    Label("Run evals", systemImage: "checklist")
                }
            }
            .disabled(isRunningEvals)

            if let report {
                ForEach(report.tiers, id: \.self) { tier in
                    tierSummaryRow(tier, in: report)
                }
                ForEach(report.results) { result in
                    evalResultRow(result)
                }
            }
        } header: {
            Text("Evaluations")
        } footer: {
            Text("Measures on-device and Private Cloud Compute on the same representative assistant tasks — extraction, classification, summarisation, reasoning — side by side, so routing is decided from data, not guesses. PCC rows run when the app is built with the iOS 27 SDK (Private Cloud Compute model); otherwise they show as pending. Third-party rows activate once a provider package is added.")
        }
    }

    private func tierSummaryRow(_ tier: ModelTier, in report: EvalReport) -> some View {
        let scored = report.results.filter { $0.tier == tier && $0.note == nil }
        return LabeledContent {
            if scored.isEmpty {
                Text("pending").foregroundStyle(.secondary)
            } else {
                Text("\(Int(report.passRate(for: tier) * 100))% · \(String(format: "%.1f", report.averageLatency(for: tier)))s avg")
            }
        } label: {
            Label(tier.shortLabel, systemImage: tier.systemImage)
        }
        .font(.subheadline.weight(.medium))
    }

    private func evalResultRow(_ result: EvalResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.note != nil ? "minus.circle" : (result.passed ? "checkmark.circle.fill" : "xmark.circle.fill"))
                .foregroundStyle(result.note != nil ? Color.secondary : (result.passed ? Color.green : Color.red))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.taskID).font(.caption.monospaced())
                Text(result.tier.shortLabel).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            if result.note == nil {
                Text("\(String(format: "%.1f", result.latency))s")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func runEvals() async {
        isRunningEvals = true
        defer { isRunningEvals = false }
        report = await EvalRunner().run()
    }

    private func ensurePolicy() {
        if policies.isEmpty {
            _ = RoutingPolicy.load(in: modelContext)
        }
    }

    // MARK: - Bindings

    /// A binding over the singleton policy that persists on every change.
    private func bind<Value>(_ keyPath: ReferenceWritableKeyPath<RoutingPolicy, Value>) -> Binding<Value> {
        Binding(
            get: { policy?[keyPath: keyPath] ?? RoutingPolicy()[keyPath: keyPath] },
            set: { newValue in
                guard let policy else { return }
                policy[keyPath: keyPath] = newValue
                policy.updatedAt = .now
                try? modelContext.save()
            }
        )
    }

    private var reasoningTierBinding: Binding<ModelTier> {
        Binding(
            get: { ModelTier(rawValue: policy?.reasoningTierRawValue ?? "") ?? .privateCloudCompute },
            set: { newValue in
                guard let policy else { return }
                policy.reasoningTierRawValue = newValue.rawValue
                policy.updatedAt = .now
                try? modelContext.save()
            }
        )
    }
}
