import SwiftUI

struct TopicChipBar: View {
    let topics: [Topic]
    var direction: LanguageDirection = .vietnameseToEnglish
    let onSelect: (Topic) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(topics.enumerated()), id: \.element.id) { index, topic in
                    Button {
                        Haptics.impact(.medium)
                        onSelect(topic)
                    } label: {
                        HStack(spacing: 4) {
                            Text(topic.emoji)
                                .font(.subheadline)
                            Text(topic.label(for: direction))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                    }
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                    .animation(.tutorSpring.delay(Double(index) * 0.05), value: topics.count)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
