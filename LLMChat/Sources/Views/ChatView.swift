import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ChatViewModel
    @State private var isInputFocused: Bool = false
    @State private var showMemoryBrowser = false
    @State private var showPersonaView = false
    @State private var showFilePicker = false

    init(agentService: AgentService, container: ModelContainer) {
        _viewModel = State(initialValue: ChatViewModel(agentService: agentService, container: container))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if !viewModel.agentService.isAvailable {
                        unavailableView
                    } else {
                        messageList
                        Divider()
                        inputBar
                    }
                }

                // Tool indicator pill
                if let indicator = viewModel.agentService.toolIndicator {
                    toolIndicatorPill(label: indicator)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(duration: 0.3), value: indicator)
                        .padding(.bottom, 72)
                }
            }
            .navigationTitle("Claw")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .navigationDestination(isPresented: $showMemoryBrowser) {
                MemoryBrowserView()
            }
            .navigationDestination(isPresented: $showPersonaView) {
                PersonaView(agentService: viewModel.agentService)
            }
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

                    // Confirmation cards inline in thread
                    if let draft = viewModel.agentService.pendingMemoryNote {
                        MemoryNoteConfirmationCard(
                            draft: draft,
                            onSave: { viewModel.confirmMemoryNote() },
                            onDiscard: { viewModel.discardMemoryNote() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id("pendingMemoryNote")
                    }

                    if let draft = viewModel.agentService.pendingMemoryUpdate {
                        MemoryUpdateConfirmationCard(
                            draft: draft,
                            onSave: { viewModel.confirmMemoryUpdate() },
                            onDiscard: { viewModel.discardMemoryUpdate() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id("pendingMemoryUpdate")
                    }

                    if let draft = viewModel.agentService.pendingPersonaUpdate {
                        PersonaUpdateConfirmationCard(
                            draft: draft,
                            onSave: { viewModel.confirmPersonaUpdate() },
                            onDiscard: { viewModel.discardPersonaUpdate() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id("pendingPersonaUpdate")
                    }

                    // Error banner inline
                    if let error = viewModel.error {
                        errorBanner(message: error)
                            .id("errorBanner")
                    }

                    // Bottom anchor for scroll
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.vertical, 12)
                .animation(.spring(duration: 0.3), value: viewModel.messages.count)
                .animation(.spring(duration: 0.3), value: viewModel.agentService.pendingMemoryNote?.id)
                .animation(.spring(duration: 0.3), value: viewModel.agentService.pendingPersonaUpdate?.id)
            }
            .onChange(of: viewModel.messages.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: viewModel.agentService.pendingMemoryNote?.id) {
                if viewModel.agentService.pendingMemoryNote != nil {
                    withAnimation { proxy.scrollTo("pendingMemoryNote", anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.error) {
                if viewModel.error != nil {
                    withAnimation { proxy.scrollTo("errorBanner", anchor: .bottom) }
                }
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            // Import file button
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
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onSubmit {
                    Task { await viewModel.sendMessage() }
                }

            // Mic placeholder (v1 stub)
            Button(action: {}) {
                Image(systemName: "mic")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
                    .frame(width: 36, height: 36)
            }
            .disabled(true)
            .accessibilityLabel("Voice input (coming soon)")

            // Send button
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
            ProgressView()
                .scaleEffect(0.7)
                .tint(.secondary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            .ultraThinMaterial,
            in: Capsule()
        )
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    // MARK: - Unavailable View

    private var unavailableView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Apple Intelligence Required")
                .font(.title2.weight(.semibold))

            Text("Claw requires Apple Intelligence. Enable it in Settings → Apple Intelligence & Siri, then run Claw on a supported device.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
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
                Image(systemName: "person.crop.circle")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Persona")
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button("Memory", systemImage: "brain") {
                    showMemoryBrowser = true
                }
                Button("Import file", systemImage: "doc.badge.plus") {
                    showFilePicker = true
                }
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
            Task {
                await importFile(from: url)
            }
        case .failure(let error):
            viewModel.error = "Failed to open file picker: \(error.localizedDescription)"
        }
    }

    private func importFile(from url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            viewModel.error = "Could not access the selected file."
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let text = try extractText(from: url)
            let preview = String(text.prefix(500))
            let filename = url.lastPathComponent

            let context = ModelContext(modelContext.container)
            let file = ImportedFile(filename: filename, contentPreview: preview, fullText: text)
            context.insert(file)
            try context.save()

            // Confirm in chat
            let confirmMsg = ChatMessage(
                role: "assistant",
                content: "I've loaded **\(filename)**. I can reference it when relevant."
            )
            viewModel.messages.append(confirmMsg)
        } catch {
            viewModel.error = "Failed to import file: \(error.localizedDescription)"
        }
    }

    private func extractText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)

        // PDF extraction (stub — real PDF extraction requires PDFKit)
        if url.pathExtension.lowercased() == "pdf" {
            // TODO: Use PDFKit for real PDF text extraction
            // NOTE: Stubbed — returning placeholder until PDFKit is integrated
            return "[PDF content from \(url.lastPathComponent) — text extraction not yet implemented. Add PDFKit for full support.]"
        }

        // RTF: try to parse as attributed string
        if url.pathExtension.lowercased() == "rtf" {
            if let attrStr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            ) {
                return attrStr.string
            }
        }

        // Plain text and markdown
        return String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
    }
}
