import SwiftUI

struct ChatView: View {
    @State private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @Namespace private var pillNamespace

    // Name capture: shown on first launch
    @State private var showNameCapture = true

    // Debug: Session Lab accessible via toolbar menu
    @State private var showSessionLab = false

    private var dir: LanguageDirection { viewModel.direction }

    var body: some View {
        Group {
            if showSessionLab {
                TabView {
                    Tab(dir == .vietnameseToEnglish ? "Gia su" : "Tutor", systemImage: "graduationcap.fill") {
                        tutorView
                    }
                    Tab("Session Lab", systemImage: "slider.horizontal.3") {
                        CustomizationChatView()
                    }
                }
            } else {
                tutorView
            }
        }
        .sheet(isPresented: $showNameCapture) {
            NameCaptureSheet(isPresented: $showNameCapture) { name, direction in
                viewModel.setLearnerName(name, direction: direction)
            }
        }
    }

    // MARK: - Main Tutor View

    private var tutorView: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    if viewModel.isModelUnavailable {
                        UnavailableView(reason: viewModel.unavailabilityReason)
                    } else {
                        // Zone 1 — Thread
                        messageList

                        // Error banner
                        if let errorMessage = viewModel.errorMessage {
                            errorBanner(message: errorMessage)
                        }

                        Divider()

                        // Zone 2 — Contextual layer (status pill, chips, quick replies)
                        zone2Layer

                        // Input bar (hidden during flashcard full-screen)
                        if !viewModel.isShowingFlashcards {
                            inputBar
                        }
                    }
                }

                // Zone 3 — Exercise overlay (floats above input bar)
                if viewModel.isShowingExercise, let exercise = viewModel.currentExercise {
                    exerciseOverlay(exercise: exercise)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.tutorSpring, value: viewModel.isShowingExercise)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            // Zone 3 — Word grid (medium detent sheet)
            .sheet(isPresented: $viewModel.isShowingWordGrid) {
                WordGridSheet(
                    words: viewModel.currentWords,
                    selectedWords: $viewModel.selectedWords,
                    direction: dir,
                    onConfirm: { Task { await viewModel.confirmWordSelection() } },
                    onDismiss: { viewModel.isShowingWordGrid = false }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            // Zone 3 — Flashcard deck (large detent sheet)
            .sheet(isPresented: $viewModel.isShowingFlashcards) {
                FlashcardSheet(
                    flashcards: viewModel.flashcards,
                    flashcardImages: viewModel.flashcardImages,
                    direction: dir,
                    onFinish: { Task { await viewModel.finishFlashcardReview() } }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: - Navigation

    private var navigationTitle: String {
        if let name = viewModel.learnerProfile?.name {
            return dir == .vietnameseToEnglish ? "Xin chao, \(name)!" : "Hello, \(name)!"
        }
        return dir == .vietnameseToEnglish ? "Gia su tieng Anh" : "Vietnamese Tutor"
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    viewModel.clearConversation()
                } label: {
                    Label(dir == .vietnameseToEnglish ? "Bat dau lai" : "Start over", systemImage: "arrow.counterclockwise")
                }
                Button {
                    showSessionLab.toggle()
                } label: {
                    Label("Session Lab", systemImage: "slider.horizontal.3")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(viewModel.isGenerating)
        }
    }

    // MARK: - Zone 1: Thread

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message).id(message.id)
                    }

                    // Inline feedback card
                    if let feedback = viewModel.currentFeedback {
                        FeedbackCard(feedback: feedback, direction: dir)
                            .padding(.horizontal)
                            .id("feedbackCard")
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.tutorSpring, value: viewModel.currentFeedback != nil)
                    }

                    // Streaming / typing indicator
                    if viewModel.isGenerating {
                        if viewModel.streamingContent.isEmpty {
                            TypingIndicatorView().id("typing-indicator")
                        } else {
                            MessageBubble(message: Message(
                                role: .assistant,
                                content: viewModel.streamingContent
                            ))
                            .id("streaming-bubble")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { scrollToBottom(proxy: proxy) }
            .onChange(of: viewModel.currentFeedback != nil) {
                withAnimation { proxy.scrollTo("feedbackCard", anchor: .bottom) }
            }
            .onChange(of: viewModel.isGenerating) {
                if viewModel.isGenerating {
                    withAnimation { proxy.scrollTo("typing-indicator", anchor: .bottom) }
                }
            }
            .onChange(of: viewModel.streamingContent) {
                withAnimation { proxy.scrollTo("streaming-bubble", anchor: .bottom) }
            }
        }
    }

    // MARK: - Zone 2: Contextual Layer

    private var zone2Layer: some View {
        VStack(spacing: 0) {
            // Status pill morphs into sheet handle via matchedGeometryEffect
            if let status = viewModel.statusMessage {
                HStack {
                    Spacer()
                    StatusPill(message: status, namespace: pillNamespace)
                    Spacer()
                }
                .padding(.vertical, 6)
            }

            // Topic chips
            if !viewModel.topics.isEmpty {
                TopicChipBar(topics: viewModel.topics, direction: dir) { topic in
                    Task { await viewModel.selectTopic(topic) }
                }
            }

            // Quick reply chips
            if !viewModel.quickReplies.isEmpty {
                QuickReplyBar(replies: viewModel.quickReplies, direction: dir) { reply in
                    Task { await viewModel.handleQuickReply(reply) }
                }
            }
        }
        .animation(.tutorSpring, value: viewModel.statusMessage)
        .animation(.tutorSpring, value: viewModel.topics.count)
        .animation(.tutorSpring, value: viewModel.quickReplies.count)
    }

    // MARK: - Zone 3: Exercise Overlay

    private func exerciseOverlay(exercise: Exercise) -> some View {
        VStack {
            Spacer()
            ExerciseOverlay(
                exercise: exercise,
                exerciseIndex: viewModel.currentExerciseIndex,
                totalExercises: viewModel.practiceRound?.exercises.count ?? 1,
                progress: viewModel.exerciseProgress,
                direction: dir,
                onAnswer: { answer in Task { await viewModel.submitAnswer(answer) } }
            )
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .background(
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture { } // absorb taps to prevent dismissal
        )
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            TextField(dir == .vietnameseToEnglish ? "Nhan tin..." : "Message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit { sendMessage() }
                .disabled(viewModel.phase != .freeChat)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(canSend ? .blue : .gray)
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
            && viewModel.phase == .freeChat
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !viewModel.isGenerating else { return }
        inputText = ""
        isInputFocused = false
        Task { await viewModel.sendMessage(text) }
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline).foregroundStyle(.primary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.12))
        .overlay(alignment: .top) {
            Divider().overlay(Color.orange.opacity(0.4))
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = viewModel.messages.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
    }
}

// MARK: - Supporting Views (moved here to avoid separate file duplication)

struct UnavailableView: View {
    let reason: String?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text("Feature unavailable")
                .font(.title2)
                .fontWeight(.semibold)

            Text(reason ?? "This device does not support Apple Intelligence. A compatible device running iOS 26 or later is required.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

struct TypingIndicatorView: View {
    @State private var animationPhase = 0

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animationPhase == index ? 1.3 : 1.0)
                        .animation(
                            .easeInOut(duration: 0.4)
                                .repeatForever()
                                .delay(Double(index) * 0.15),
                            value: animationPhase
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer()
        }
        .onAppear { animationPhase = 1 }
    }
}

#Preview {
    ChatView()
}
