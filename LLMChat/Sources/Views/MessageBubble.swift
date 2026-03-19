import SwiftUI

struct MessageBubble: View {
    let message: ChatMessage
    let onSaveToMemory: () -> Void

    private var isUser: Bool { message.role == "user" }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            } else {
                avatarView
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                bubbleView
                if !message.toolCallsMade.isEmpty {
                    toolCallBadges
                }
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Components

    private var avatarView: some View {
        Text("◈")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(Color(.systemGray5), in: Circle())
    }

    private var bubbleView: some View {
        Group {
            if message.isStreaming && message.content.isEmpty {
                thinkingDots
            } else {
                Text(message.content)
                    .textSelection(.enabled)
                    .font(.body)
                    .foregroundStyle(isUser ? Color.white : Color.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(isUser ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.secondarySystemBackground)))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contextMenu {
            if !isUser {
                Button("Save to memory", systemImage: "brain") {
                    onSaveToMemory()
                }
            }
            Button("Copy", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = message.content
            }
        }
    }

    private var thinkingDots: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                ThinkingDot(delay: Double(i) * 0.18)
            }
        }
        .padding(.vertical, 4)
    }

    private var toolCallBadges: some View {
        HStack(spacing: 4) {
            Image(systemName: "wrench.adjustable")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            ForEach(message.toolCallsMade, id: \.self) { tool in
                Text(tool)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5), in: Capsule())
            }
        }
        .padding(.leading, isUser ? 0 : 4)
        .padding(.trailing, isUser ? 4 : 0)
    }
}

// MARK: - Thinking Dot

private struct ThinkingDot: View {
    let delay: Double
    @State private var opacity: Double = 0.3

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 7, height: 7)
            .opacity(opacity)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.55)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) {
                    opacity = 1.0
                }
            }
    }
}

import UIKit
