import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AgentKit

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var showMemoryBrowser = false
    @State private var showPersonaView = false
    @State private var showFilePicker = false

    private let engine: ConversationEngine

    init(engine: ConversationEngine, container: ModelContainer) {
        self.engine = engine
        _viewModel = State(initialValue: ChatViewModel(engine: engine, container: container))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    messageList
                    Divider()
                    inputBar
                }

                if let indicator = engine.toolIndicator {
                    toolIndicatorPill(label: indicator)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(duration: 0.3), value: indicator)
                        .padding(.bottom, 72)
                }
            }
            .navigationTitle("Claw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(isPresented: $showMemoryBrowser) { MemoryBrowserView() }
            .navigationDestination(isPresented: $showPersonaView) { PersonaView(engine: engine) }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .pdf, .rtf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
        }
        .task { await viewModel.startSession() }
        .onDisappear { viewModel.endSession() }
        .onChange(of: isInputFocused) { _, focused in
            if focused { engine.prewarm() }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message) {
                            viewModel.proposeMemoryFromMessage(message)
                        }
                        .id(message.id)
                    }

                    confirmationCards

                    if let error = viewModel.error {
                        errorBanner(message: error).id("errorBanner")
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 12)
                .animation(.spring(duration: 0.3), value: viewModel.messages.count)
                .animation(.spring(duration: 0.3), value: viewModel.approvalGate.pendingMemoryNote?.id)
                .animation(.spring(duration: 0.3), value: viewModel.approvalGate.pendingPersonaUpdate?.id)
                .animation(.spring(duration: 0.3), value: viewModel.approvalGate.pendingReminder?.id)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.error) {
                if viewModel.error != nil { withAnimation { proxy.scrollTo("errorBanner", anchor: .bottom) } }
            }
        }
    }

    @ViewBuilder
    private var confirmationCards: some View {
        if let draft = viewModel.approvalGate.pendingMemoryNote {
            MemoryNoteConfirmationCard(
                draft: draft,
                onSave: { viewModel.confirmMemoryNote() },
                onDiscard: { viewModel.discardMemoryNote() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id("pendingMemoryNote")
        }

        if let draft = viewModel.approvalGate.pendingMemoryUpdate {
            MemoryUpdateConfirmationCard(
                draft: draft,
                onSave: { viewModel.confirmMemoryUpdate() },
                onDiscard: { viewModel.discardMemoryUpdate() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id("pendingMemoryUpdate")
        }

        if let draft = viewModel.approvalGate.pendingPersonaUpdate {
            PersonaUpdateConfirmationCard(
                draft: draft,
                onSave: { viewModel.confirmPersonaUpdate() },
                onDiscard: { viewModel.discardPersonaUpdate() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id("pendingPersonaUpdate")
        }

        if let draft = viewModel.approvalGate.pendingReminder {
            ReminderConfirmationCard(
                draft: draft,
                onConfirm: { viewModel.confirmReminder() },
                onDiscard: { viewModel.discardReminder() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id("pendingReminder")
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Button(action: { showFilePicker = true }) {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Import file")

            TextField("Message…", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit { Task { await viewModel.sendMessage() } }

            Button(action: {}) {
                Image(systemName: "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
            }
            .disabled(true)
            .accessibilityLabel("Voice input (arrives in Phase 7)")

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

    // MARK: - Tool Indicator

    private func toolIndicatorPill(label: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().scaleEffect(0.7).tint(.secondary)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline).foregroundStyle(.primary)
            Spacer()
            Button("Dismiss") { viewModel.error = nil }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.orange)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.1))
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { showPersonaView = true }) {
                Image(systemName: "person.crop.circle").foregroundStyle(.secondary)
            }
            .accessibilityLabel("Persona")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Memory", systemImage: "brain") { showMemoryBrowser = true }
                Button("Import file", systemImage: "doc.badge.plus") { showFilePicker = true }
                Divider()
                Button("Clear conversation", systemImage: "trash", role: .destructive) {
                    viewModel.clearConversation()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - File Import

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                viewModel.error = "Could not access the selected file."
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            viewModel.importFile(from: url)
        case .failure(let error):
            viewModel.error = "Failed to open file picker: \(error.localizedDescription)"
        }
    }
}
