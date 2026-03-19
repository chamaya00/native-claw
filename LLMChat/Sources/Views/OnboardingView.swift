import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: OnboardingViewModel
    let onComplete: () -> Void

    init(agentService: AgentService, container: ModelContainer, onComplete: @escaping () -> Void) {
        _viewModel = State(initialValue: OnboardingViewModel(agentService: agentService, container: container))
        self.onComplete = onComplete
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                header

                // Message thread
                messageList

                Divider()

                // Input or confirmation
                if let preview = viewModel.personaPreview {
                    personaConfirmBar(preview: preview)
                } else {
                    inputBar
                }
            }
        }
        .task { await viewModel.startOnboarding() }
        .onChange(of: viewModel.isComplete) { _, complete in
            if complete { onComplete() }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 4) {
            Text("◈ Meet Claw")
                .font(.title3.weight(.semibold))
            Text("Your private AI agent. Let's set it up — just talk.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, onSaveToMemory: {})
                            .id(message.id)
                    }

                    if let error = viewModel.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 12)
                .animation(.spring(duration: 0.3), value: viewModel.messages.count)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Tell Claw about yourself…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit { Task { await viewModel.sendMessage() } }

            Button(action: { Task { await viewModel.sendMessage() } }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isResponding
    }

    // MARK: - Persona Confirm Bar

    private func personaConfirmBar(preview: OnboardingViewModel.PersonaPreview) -> some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Your Claw")
                    .font(.subheadline.weight(.semibold))

                Group {
                    previewRow(label: "Purpose", value: preview.purpose)
                    previewRow(label: "Tone", value: preview.tone)
                    previewRow(label: "Values", value: preview.values.joined(separator: ", "))
                    previewRow(label: "Focus", value: preview.expertiseAreas.joined(separator: ", "))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack(spacing: 10) {
                Button("Adjust") {
                    viewModel.personaPreview = nil
                }
                .font(.footnote.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.primary)

                Button("This is me →") {
                    do {
                        try viewModel.confirmPersona()
                    } catch {
                        viewModel.error = error.localizedDescription
                    }
                }
                .font(.footnote.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label + ":")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
        }
    }
}
