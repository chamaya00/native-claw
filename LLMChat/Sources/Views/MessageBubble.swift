import SwiftUI

struct MessageBubble: View {
    let message: Message

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                assistantAvatar
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleContent
                timestampLabel
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }

    private var assistantAvatar: some View {
        Image(systemName: "brain.head.profile")
            .font(.system(size: 16))
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(Color.purple.gradient)
            .clipShape(Circle())
    }

    private var bubbleContent: some View {
        Text(message.content)
            .font(.body)
            .foregroundStyle(isUser ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(bubbleBackground)
            .clipShape(BubbleShape(isUser: isUser))
    }

    private var bubbleBackground: some ShapeStyle {
        if isUser {
            return AnyShapeStyle(Color.blue.gradient)
        } else {
            return AnyShapeStyle(Color(.secondarySystemBackground))
        }
    }

    private var timestampLabel: some View {
        Text(message.timestamp.formatted(.dateTime.hour().minute()))
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

struct BubbleShape: Shape {
    let isUser: Bool
    private let cornerRadius: CGFloat = 18
    private let tailRadius: CGFloat = 4

    func path(in rect: CGRect) -> Path {
        var path = Path()

        let topLeft = CGPoint(x: rect.minX + cornerRadius, y: rect.minY)
        let topRight = CGPoint(x: rect.maxX - cornerRadius, y: rect.minY)
        let bottomRight = CGPoint(x: rect.maxX - (isUser ? tailRadius : cornerRadius), y: rect.maxY)
        let bottomLeft = CGPoint(x: rect.minX + (isUser ? cornerRadius : tailRadius), y: rect.maxY)

        path.move(to: topLeft)
        path.addLine(to: topRight)
        path.addArc(
            center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )

        if isUser {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tailRadius))
            path.addArc(
                center: CGPoint(x: rect.maxX - tailRadius, y: rect.maxY - tailRadius),
                radius: tailRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
        } else {
            path.addLine(to: bottomRight)
        }

        path.addLine(to: bottomLeft)

        if !isUser {
            path.addArc(
                center: CGPoint(x: rect.minX + tailRadius, y: rect.maxY - tailRadius),
                radius: tailRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
        }

        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
        path.addArc(
            center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
            radius: cornerRadius,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )

        path.closeSubpath()
        return path
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubble(message: Message(role: .user, content: "Hello! Can you help me understand quantum computing?"))
        MessageBubble(message: Message(role: .assistant, content: "Of course! Quantum computing uses quantum bits (qubits) instead of classical bits. Unlike classical bits that are either 0 or 1, qubits can exist in a superposition of both states simultaneously."))
    }
    .padding()
}
