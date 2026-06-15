import SwiftUI
import AgentKit

/// Phase 0 graceful fallback shown whenever the on-device model is unavailable.
/// The message is specific to the availability reason (device, AI disabled, model
/// downloading, or unsupported build).
struct AvailabilityUnavailableView: View {
    let state: AvailabilityState

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: iconName)
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Apple Intelligence Required")
                .font(.title2.weight(.semibold))

            Text(state.userMessage)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var iconName: String {
        switch state {
        case .modelNotReady: return "arrow.down.circle"
        case .appleIntelligenceNotEnabled: return "switch.2"
        default: return "exclamationmark.triangle.fill"
        }
    }
}
