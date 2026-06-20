import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import AgentKit

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool
    @State private var showMemoryBrowser = false
    @State private var showPersonaView = false
    @State private var showRoutingSettings = false
    @State private var showSuggestions = false
    @State private var showFilePicker = false
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

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
            .navigationDestination(isPresented: $showRoutingSettings) { RoutingSettingsView(engine: engine) }
            .navigationDestination(isPresented: $showSuggestions) { SuggestionInboxView() }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .pdf, .rtf],
                allowsMultipleSelection: false
            ) { result in
                handleFileImport(result)
            }
            .photosPicker(
                isPresented: $showPhotoPicker,
                selection: $selectedPhoto,
                matching: .images
            )
        }
        .task { await viewModel.startSession() }
        .onDisappear { viewModel.endSession() }
        .onChange(of: isInputFocused) { _, focused in
            if focused { engine.prewarm() }
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            Task { await handlePhotoSelection(item) }
        }
    }

    private func handlePhotoSelection(_ item: PhotosPickerItem) async {
        defer { selectedPhoto = nil }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                viewModel.error = "Couldn't load that image."
                return
            }
            await viewModel.attachImage(data: data, name: "Image")
        } catch {
            viewModel.error = "Couldn't load that image: \(error.localizedDescription)"
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
                .animation(.spring(duration: 0.3), value: viewModel.approvalGate.pendingCalendarEvent?.id)
                .animation(.spring(duration: 0.3), value: viewModel.pendingPreferenceChoice?.id)
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

        if let draft = viewModel.approvalGate.pendingCalendarEvent {
            CalendarEventConfirmationCard(
                draft: draft,
                onConfirm: { viewModel.confirmCalendarEvent() },
                onDiscard: { viewModel.discardCalendarEvent() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id("pendingCalendarEvent")
        }

        if let choice = viewModel.pendingPreferenceChoice {
            PreferenceChoiceCard(
                choice: choice,
                onPick: { pickedA in viewModel.choosePreference(pickedA: pickedA) },
                onSkip: { viewModel.skipPreference() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id("pendingPreferenceChoice")
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if viewModel.hasPendingImage || viewModel.isProcessingImage {
                pendingImageChip
            }
            inputControls
        }
        .background(Color(.systemBackground))
    }

    private var pendingImageChip: some View {
        HStack(spacing: 6) {
            if viewModel.isProcessingImage {
                ProgressView().scaleEffect(0.7)
                Text("Reading image…").font(.caption).foregroundStyle(.secondary)
            } else {
                Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
                Text(viewModel.pendingImageName ?? "Image attached")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Button(action: { viewModel.clearPendingImage() }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .accessibilityLabel("Remove image")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    private var inputControls: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Menu {
                Button("Photo or screenshot", systemImage: "photo") { showPhotoPicker = true }
                Button("File", systemImage: "doc") { showFilePicker = true }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("Attach")

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
        let hasText = !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || viewModel.hasPendingImage)
            && !viewModel.isResponding
            && !viewModel.isProcessingImage
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
                Button("Suggestions", systemImage: "wand.and.stars") { showSuggestions = true }
                Button("Model routing", systemImage: "arrow.triangle.branch") { showRoutingSettings = true }
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
