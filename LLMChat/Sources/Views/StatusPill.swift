import SwiftUI

struct StatusPill: View {
    let message: String
    let namespace: Namespace.ID

    @State private var glowing = false

    var body: some View {
        HStack(spacing: 6) {
            Text("✦")
                .opacity(glowing ? 1 : 0.4)
                .animation(.easeInOut(duration: 0.7).repeatForever(), value: glowing)
            Text(message)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .matchedGeometryEffect(id: "statusPill", in: namespace)
        .onAppear { glowing = true }
        .transition(.asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .opacity
        ))
    }
}
