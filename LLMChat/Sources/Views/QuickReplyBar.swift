import SwiftUI

struct QuickReplyBar: View {
    let replies: [QuickReply]
    var direction: LanguageDirection = .vietnameseToEnglish
    let onSelect: (QuickReply) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(replies.enumerated()), id: \.element.id) { index, reply in
                    Button {
                        Haptics.impact(.light)
                        onSelect(reply)
                    } label: {
                        Text(reply.label(for: direction))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.blue.opacity(0.3), lineWidth: 1))
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.tutorSpring.delay(Double(index) * 0.05), value: replies.count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
