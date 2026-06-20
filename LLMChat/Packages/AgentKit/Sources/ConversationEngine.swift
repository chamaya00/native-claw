import Foundation
import SwiftData
import Observation
import MemoryKit
import ToolsKit

#if canImport(FoundationModels)
import FoundationModels
#endif

public enum AgentError: LocalizedError {
    case modelUnavailable(AvailabilityState)
    case sessionNotInitialized

    public var errorDescription: String? {
        switch self {
        case .modelUnavailable(let state):
            return state.userMessage
        case .sessionNotInitialized:
            return "The assistant session isn't ready yet. Try again in a moment."
        }
    }
}

/// Owns the `LanguageModelSession`, drives turns (streaming), dispatches tools through
/// the `ApprovalGate`, enforces the `ContextBudget`, and persists the transcript to
/// SwiftData. This is the conversation spine — everything else hangs off it.
@Observable
@MainActor
public final class ConversationEngine {

    // MARK: Public state (observed by the UI)

    public let availability: AvailabilityService
    public let approvalGate: ApprovalGate
    public let router: ModelRouter
    public var toolIndicator: String?
    public private(set) var currentConversationID: UUID?

    /// The tier that backed the most recent assistant turn, surfaced as a transparency
    /// chip so the user always knows where their data went (§Phase 4).
    public private(set) var lastResponseTier: ModelTier?

    /// Tools that actually ran during the most recent turn (cleaned labels), surfaced
    /// to the UI as tool-call chips under the assistant bubble (§Phase 2).
    public private(set) var lastTurnToolCalls: [String] = []

    public var isAvailable: Bool { availability.isAvailable }

    // MARK: Dependencies

    private let container: ModelContainer
    private let personaStore: PersonaStore
    private let memoryManager: MemoryManager
    private let budget = ContextBudget()
    private var usedTokens = 0

    /// How many assistant turns have elapsed since the last curation pass. Curation is
    /// run periodically (not every turn) to amortise the extra model call (§Phase 3).
    private var turnsSinceCuration = 0
    private var didReindexSpotlight = false
    private static let curationInterval = 4

    /// The tool names currently attached to the live session. Dynamic tool selection
    /// only *grows* this set when a turn needs a tool that isn't attached yet — so a
    /// short conversation never pays the token cost of tools it never uses (§Phase 2).
    /// Seeded with `ToolSelector.coreToolNames` in `start()` (gated on FoundationModels).
    private var attachedToolNames: Set<String> = []
    /// Cleaned tool labels collected during the in-flight turn.
    private var turnToolCalls: [String] = []

#if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var onboardingSession: LanguageModelSession?
#endif

    public init(container: ModelContainer) {
        self.container = container
        self.availability = AvailabilityService()
        self.approvalGate = ApprovalGate(container: container)
        self.router = ModelRouter(container: container)
        self.personaStore = PersonaStore(container: container)
        self.memoryManager = MemoryManager(container: container)
        // Make stored memory resolvable by the system (Spotlight/Siri) — App Intents
        // queries are created by the OS and can't see the injected container otherwise.
        MemoryEntityBridge.register(container: container)
    }

    // MARK: - Session lifecycle

    public func start() async throws {
        availability.refresh()
        guard availability.isAvailable else {
            throw AgentError.modelUnavailable(availability.state)
        }
#if canImport(FoundationModels)
        attachedToolNames = ToolSelector.coreToolNames
#endif
        buildSession(condensedSummary: nil)
        if currentConversationID == nil {
            currentConversationID = createConversation()
        }
        // Reconcile the Spotlight index with the store once per launch — picks up facts
        // mirrored in from another device since last run (§Phase 3 cross-device recall).
        if !didReindexSpotlight {
            didReindexSpotlight = true
            MemorySpotlightIndexer.reindexAll(container: container)
        }
    }

    public func invalidate() {
#if canImport(FoundationModels)
        session = nil
        onboardingSession = nil
#endif
        approvalGate.clearAll()
        toolIndicator = nil
    }

    public func clearConversation() async {
        invalidate()
        currentConversationID = createConversation()
        pruneOldConversations()
        try? await start()
    }

    /// Warm the model when the input field gains focus (latency win on a small model).
    public func prewarm() {
#if canImport(FoundationModels)
        session?.prewarm()
#endif
    }

    private func buildSession(condensedSummary: String?) {
#if canImport(FoundationModels)
        let context = ModelContext(container)
        let persona = personaStore.currentPersona()
        let recent = searchMemories(query: "recent context active goals", context: context, limit: 3)
        let instructions = personaStore.systemInstructions(
            persona: persona,
            topMemories: recent,
            condensedSummary: condensedSummary
        )
        session = LanguageModelSession(
            tools: buildTools(
                container: container,
                onEvent: makeEventHandler(),
                selecting: attachedToolNames
            ),
            instructions: instructions
        )
        usedTokens = budget.estimatedTokens(instructions)
        session?.prewarm()
#endif
    }

    // MARK: - Streaming turn

    /// Stream an assistant response. Each yielded value is the cumulative snapshot of
    /// the response so far (idiomatic FoundationModels partial-snapshot streaming) —
    /// bind it straight to SwiftUI state. The user turn is persisted immediately and
    /// the final assistant turn on completion.
    public func streamResponse(to text: String, hasImage: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try await self.runTurn(text: text, hasImage: hasImage, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func runTurn(
        text: String,
        hasImage: Bool,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        persist(role: "user", content: text)
        usedTokens += budget.estimatedTokens(text)
        turnToolCalls = []
        lastTurnToolCalls = []

        // Route the turn (§Phase 4): pick the model tier from policy + token pressure, and
        // budget against *that* tier's window. Pure policy — safe outside the FM gate.
        let resolution = router.resolve(task: .chat, estimatedPromptTokens: usedTokens)
        lastResponseTier = resolution.boundTier

#if canImport(FoundationModels)
        let activeBudget = ContextBudget(contextSize: resolution.contextSize)

        // Dynamic tool selection (§Phase 2): grow the attached tool set only when this
        // turn plausibly needs a tool we haven't attached yet, then re-seat the session.
        let needed = attachedToolNames.union(
            ToolSelector.selectedToolNames(for: text, hasImage: hasImage)
        )
        let toolsChanged = needed != attachedToolNames

        // Proactively summarise before we risk overflowing the window. Re-seating also
        // rebuilds the session, so fold a needed tool-set change into the same rebuild.
        if activeBudget.shouldSummarize(usedTokens: usedTokens) || toolsChanged {
            attachedToolNames = needed
            await reseatWithSummary()
        }

        guard let session else { throw AgentError.sessionNotInitialized }
        var finalText = ""
        do {
            finalText = try await stream(session: session, text: text, continuation: continuation)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Typed recovery (never match on localizedDescription): re-seat a fresh
            // session seeded with a condensed transcript, then retry the turn once.
            await reseatWithSummary()
            guard let retry = self.session else { throw AgentError.sessionNotInitialized }
            finalText = try await stream(session: retry, text: text, continuation: continuation)
        }
        usedTokens += budget.estimatedTokens(finalText)
        lastTurnToolCalls = turnToolCalls
        persist(role: "assistant", content: finalText, toolCalls: turnToolCalls)
        maybeCurateMemory()
#else
        let stub = "⚠️ Foundation Models is not available in this build. Run on a device with Apple Intelligence enabled."
        continuation.yield(stub)
        persist(role: "assistant", content: stub)
#endif
    }

#if canImport(FoundationModels)
    private func stream(
        session: LanguageModelSession,
        text: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws -> String {
        var latest = ""
        for try await partial in session.streamResponse(to: text) {
            latest = partial.content
            continuation.yield(partial.content)
        }
        return latest
    }
#endif

    /// Periodically distil durable facts from the conversation into the review inbox.
    /// Runs off the streaming path (a separate model call) and never blocks the turn or
    /// surfaces failures — curation is best-effort background work (§Phase 3).
    private func maybeCurateMemory() {
        turnsSinceCuration += 1
        guard turnsSinceCuration >= Self.curationInterval else { return }
        turnsSinceCuration = 0
        let recent = fetchRecentMessages(limit: 12)
        let manager = memoryManager
        Task { @MainActor in
            await manager.curate(recentMessages: recent)
        }
    }

    private func reseatWithSummary() async {
        let summary = (try? await budget.summarize(messages: fetchRecentMessages(limit: 20))) ?? ""
        buildSession(condensedSummary: summary.isEmpty ? nil : summary)
    }

    // MARK: - Onboarding

    public func startOnboarding() {
#if canImport(FoundationModels)
        onboardingSession = LanguageModelSession(instructions: Self.onboardingInstructions)
#endif
    }

    public func onboardingRespond(to text: String) async throws -> String {
#if canImport(FoundationModels)
        guard let onboardingSession else { throw AgentError.sessionNotInitialized }
        return try await onboardingSession.respond(to: text).content
#else
        return "Foundation Models is not available in this build. Run on a device with Apple Intelligence enabled."
#endif
    }

    public func extractPersona() async throws -> PersonaDraft {
#if canImport(FoundationModels)
        guard let onboardingSession else { throw AgentError.sessionNotInitialized }
        let response = try await onboardingSession.respond(
            to: "Based on our conversation, extract a structured persona definition including the name the user chose.",
            generating: PersonaDraft.self
        )
        return response.content
#else
        return PersonaDraft(
            name: "Claw",
            vibe: "Direct and helpful",
            values: ["concise", "honest"],
            expertiseAreas: ["productivity", "writing"]
        )
#endif
    }

    private static let onboardingInstructions = """
    You are a blank-slate AI assistant being shaped by the user right now. \
    You have no name, no vibe, nothing yet.

    Your job is to have a relaxed, natural conversation to figure out:
    1. What they want to name you
    2. What vibe or energy they want you to carry — not "how do you want me to make you feel", \
       just ask something like "what kind of vibe are you going for?" or "chill and casual, \
       or something else?"
    3. Optionally, what topics or areas they care about (don't force this)

    Rules:
    - Keep it casual and loose. Short messages, one idea at a time.
    - Don't be stiff or formal. Sound like a person, not a setup wizard.
    - No bullet points, headers, or markdown — just plain conversational text.
    - Don't explain what you're doing or why. Just ask and listen.
    - Once you have a name, use it naturally.
    - After 3 or more user responses, you have enough to wrap up.
    """

    // MARK: - Tool event routing

    private func makeEventHandler() -> @MainActor @Sendable (ToolEvent) -> Void {
        let gate = approvalGate
        return { [weak self] event in
            switch event {
            case .toolStarted(let label):
                self?.toolIndicator = label
                self?.recordToolCall(label)
            case .toolCompleted:
                self?.toolIndicator = nil
            default:
                gate.submit(event)
            }
        }
    }

    /// Turn a progress label ("Searching memory…") into a compact chip ("Searching memory")
    /// and dedupe it for the turn's tool-call record.
    private func recordToolCall(_ label: String) {
        let cleaned = label.trimmingCharacters(in: CharacterSet(charactersIn: "… ."))
        guard !cleaned.isEmpty, !turnToolCalls.contains(cleaned) else { return }
        turnToolCalls.append(cleaned)
    }

    // MARK: - Persistence

    private func createConversation() -> UUID {
        let context = ModelContext(container)
        let conversation = Conversation()
        context.insert(conversation)
        try? context.save()
        return conversation.id
    }

    private func persist(role: String, content: String, toolCalls: [String] = []) {
        guard let id = currentConversationID else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })
        guard let conversation = (try? context.fetch(descriptor))?.first else { return }
        let message = Message(role: role, content: content, toolCallsMade: toolCalls)
        message.conversation = conversation
        conversation.messages.append(message)
        try? context.save()
    }

    private func fetchRecentMessages(limit: Int) -> [ChatMessage] {
        guard let id = currentConversationID else { return [] }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.id == id })
        guard let conversation = (try? context.fetch(descriptor))?.first else { return [] }
        return conversation.messages
            .sorted { $0.timestamp < $1.timestamp }
            .suffix(limit)
            .map { ChatMessage(role: $0.role, content: $0.content) }
    }

    private func pruneOldConversations(keeping limit: Int = 10) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let all = try? context.fetch(descriptor), all.count > limit else { return }
        for conversation in all.dropFirst(limit) {
            context.delete(conversation)
        }
        try? context.save()
    }
}
