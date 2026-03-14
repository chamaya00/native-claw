import SwiftUI

struct CustomizationChatView: View {
    @State private var viewModel = CustomizationViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedTab: ContentTab = .chat
    @State private var showSettings = true

    enum ContentTab: String, CaseIterable {
        case chat = "Chat"
        case transcript = "Transcript"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.isModelUnavailable {
                    UnavailableView(reason: viewModel.unavailabilityReason)
                } else {
                    settingsPanel
                    Divider()
                    contentTabPicker
                    Divider()
                    contentArea
                    if let errorMessage = viewModel.errorMessage {
                        errorBanner(message: errorMessage)
                    }
                    Divider()
                    inputBar
                }
            }
            .navigationTitle("Session Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        viewModel.applySettings()
                        selectedTab = .chat
                    } label: {
                        Label("Reset Session", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isGenerating)
                }
            }
        }
    }

    // MARK: - Settings Panel

    private var settingsPanel: some View {
        DisclosureGroup(isExpanded: $showSettings) {
            VStack(alignment: .leading, spacing: 14) {
                instructionsField
                samplingPicker
                if !viewModel.useGreedySampling {
                    temperatureSlider
                }
                applyButton
            }
            .padding(.top, 4)
            .padding(.bottom, 8)
        } label: {
            Label("Session Configuration", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var instructionsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Instructions", systemImage: "text.bubble")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $viewModel.instructions)
                .font(.body)
                .frame(minHeight: 56, maxHeight: 100)
                .padding(6)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.separator), lineWidth: 0.5)
                )
                .disabled(viewModel.isGenerating)
        }
    }

    private var samplingPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Sampling Strategy", systemImage: "dice")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Sampling", selection: $viewModel.useGreedySampling) {
                Text("Temperature").tag(false)
                Text("Greedy (Deterministic)").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(viewModel.isGenerating)
        }
    }

    private var temperatureSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Temperature", systemImage: "thermometer.medium")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", viewModel.temperature))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                Text("Focused")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Slider(value: $viewModel.temperature, in: 0.0...2.0, step: 0.05)
                    .tint(.blue)
                    .disabled(viewModel.isGenerating)
                Text("Creative")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var applyButton: some View {
        Button {
            viewModel.applySettings()
            selectedTab = .chat
        } label: {
            Label("Apply & Reset Session", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.purple)
        .disabled(viewModel.isGenerating)
    }

    // MARK: - Tab Picker

    private var contentTabPicker: some View {
        Picker("View", selection: $selectedTab) {
            ForEach(ContentTab.allCases, id: \.self) { tab in
                HStack(spacing: 4) {
                    Image(systemName: tab == .chat ? "bubble.left.and.bubble.right" : "list.bullet.rectangle")
                    Text(tab.rawValue)
                }
                .tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        switch selectedTab {
        case .chat:
            messageList
        case .transcript:
            transcriptList
        }
    }

    // MARK: - Message List (Chat Tab)

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isGenerating {
                        if viewModel.streamingContent.isEmpty {
                            TypingIndicatorView()
                                .id("lab-typing-indicator")
                        } else {
                            MessageBubble(message: Message(
                                role: .assistant,
                                content: viewModel.streamingContent
                            ))
                            .id("lab-streaming-bubble")
                        }
                    }

                    if viewModel.messages.isEmpty && !viewModel.isGenerating {
                        emptyStateHint
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.isGenerating) {
                if viewModel.isGenerating {
                    withAnimation { proxy.scrollTo("lab-typing-indicator", anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.streamingContent) {
                withAnimation { proxy.scrollTo("lab-streaming-bubble", anchor: .bottom) }
            }
        }
    }

    private var emptyStateHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 36))
                .foregroundStyle(.purple.opacity(0.5))
            Text("Configure the session above, then send a message.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Transcript List (Transcript Tab)

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if viewModel.transcriptEntries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 36))
                                .foregroundStyle(.secondary.opacity(0.5))
                            Text("The session transcript will appear here after your first message.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        ForEach(viewModel.transcriptEntries) { entry in
                            TranscriptEntryRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.transcriptEntries.count) {
                if let last = viewModel.transcriptEntries.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendMessage() }

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? .purple : .gray)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isGenerating
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isGenerating else { return }
        inputText = ""
        isInputFocused = false
        selectedTab = .chat
        Task { await viewModel.sendMessage(text) }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .top) {
            Divider().overlay(Color.orange.opacity(0.4))
        }
    }
}

// MARK: - Transcript Entry Row

struct TranscriptEntryRow: View {
    let entry: TranscriptDisplayEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: roleIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleColor)
                Text(entry.role)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(roleColor)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(roleColor.opacity(0.12))
            .clipShape(Capsule())

            Text(entry.content)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(roleColor.opacity(0.25), lineWidth: 1)
        )
    }

    private var roleColor: Color {
        switch entry.role {
        case "Instructions": return .purple
        case "User":         return .blue
        case "Assistant":    return .green
        default:             return .gray
        }
    }

    private var roleIcon: String {
        switch entry.role {
        case "Instructions": return "gear"
        case "User":         return "person.fill"
        case "Assistant":    return "brain"
        default:             return "circle"
        }
    }
}

#Preview {
    CustomizationChatView()
}
