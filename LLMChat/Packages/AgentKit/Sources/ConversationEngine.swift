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
    /// Offers occasional A/B style choices and records the winner (§Phase 5). Observed by
    /// the chat UI, which renders `pendingChoice` as a card.
    public let preferenceLearner: PreferenceLearner
    public var toolIndicator: String?
    public private(set) var currentConversationID: UUID?

    /// The tier that backed the most recent assistant turn, surfaced as a transparency
    /// chip so the user always knows where their data went (§Phase 4).
    public private(set) var lastResponseTier: ModelTier?

    /// Tools that actually ran during the most recent turn (cleaned labels), surfaced
    /// to the UI as tool-call chips under the assistant bubble (§Phase 2).
    public private(set) var lastTurnToolCalls: [String] = []

    /// The active conversation mode (Dynamic Profiles, §Phase 6). The default `.assistant`
    /// runs on the main session and durable transcript; an isolated profile like `.research`
    /// runs as a subagent that never touches the main conversation.
    public private(set) var activeProfile: ConversationProfile = .assistant

    /// A test override that pins every main-chat turn to one tier so the same prompt can be
    /// compared on-device vs Private Cloud Compute (§Phase 4). `nil` = normal policy routing.
    /// Still subject to the privacy lock, permissions, and PCC budget — see `ModelRouter.resolve`.
    public var forcedTier: ModelTier?

    public var isAvailable: Bool { availability.isAvailable }

    // MARK: Dependencies

    private let container: ModelContainer
    private let personaStore: PersonaStore
    private let memoryManager: MemoryManager
    private let routineSuggester: RoutineSuggester
    private let budget = ContextBudget()
    private var usedTokens = 0

    /// How many assistant turns have elapsed since the last curation pass. Curation is
    /// run periodically (not every turn) to amortise the extra model call (§Phase 3).
    private var turnsSinceCuration = 0
    /// Same idea for routine suggestion (§Phase 5), at a longer cadence — patterns need a
    /// few turns to emerge and the pass is purely opportunistic.
    private var turnsSinceSuggestion = 0
    private var didReindexSpotlight = false
    private static let curationInterval = 4
    private static let suggestionInterval = 6

    /// The tool names currently attached to the live session. Dynamic tool selection
    /// only *grows* this set when a turn needs a tool that isn't attached yet — so a
    /// short conversation never pays the token cost of tools it never uses (§Phase 2).
    /// Seeded with `ToolSelector.coreToolNames` in `start()` (gated on FoundationModels).
    private var attachedToolNames: Set<String> = []
    /// Cleaned tool labels collected during the in-flight turn.
    private var turnToolCalls: [String] = []

    /// Token usage + the handed-off context for the isolated research subagent. Tracked
    /// separately so a research thread never spends the main conversation's budget (§Phase 6).
    private var researchUsedTokens = 0
    private var researchBaton: String?

    /// The tier the live `session` is currently bound to. The session is rebuilt (re-seated
    /// with a condensed summary) whenever a routed turn resolves to a different tier, so the
    /// model that answers always matches `lastResponseTier` (§Phase 4). Mirrored for the
    /// research subagent by `researchSessionTier`.
    private var sessionTier: ModelTier = .onDevice
    private var researchSessionTier: ModelTier = .onDevice

#if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var onboardingSession: LanguageModelSession?
    /// The isolated subagent session for a context-isolating profile (e.g. `.research`).
    /// Built on demand by `activateProfile` and torn down on return to `.assistant`.
    private var researchSession: LanguageModelSession?

    /// Map a routed tier to the concrete model that backs the session (WWDC26 `LanguageModel`
    /// protocol). On-device and Private Cloud Compute are real bindings — PCC opens the 32K
    /// reasoning window with no API keys or auth. Third-party still awaits a provider SPM
    /// package, so it falls back to on-device (the router already flags that as degraded).
    ///
    /// Gated on `FM_PCC`: `LanguageModel`/`PrivateCloudComputeLanguageModel` ship in the
    /// iOS 27 SDK (Xcode 27), not the iOS 26 SDK the default build compiles against, so this
    /// is only compiled when the build opts in with `-D FM_PCC`. See `buildSession`.
#if FM_PCC
    private func model(for tier: ModelTier) -> any LanguageModel {
        switch tier {
        case .onDevice: return SystemLanguageModel.default
        case .privateCloudCompute: return PrivateCloudComputeLanguageModel()
        case .thirdParty: return SystemLanguageModel.default
        }
    }
#endif
#endif

    public init(container: ModelContainer) {
        self.container = container
        self.availability = AvailabilityService()
        self.approvalGate = ApprovalGate(container: container)
        self.router = ModelRouter(container: container)
        self.preferenceLearner = PreferenceLearner(container: container)
        self.personaStore = PersonaStore(container: container)
        self.memoryManager = MemoryManager(container: container)
        self.routineSuggester = RoutineSuggester(container: container)
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
        researchSession = nil
#endif
        activeProfile = .assistant
        researchBaton = nil
        researchUsedTokens = 0
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

    private func buildSession(condensedSummary: String?, tier: ModelTier = .onDevice) {
        sessionTier = tier
#if canImport(FoundationModels)
        let context = ModelContext(container)
        let persona = personaStore.currentPersona()
        let recent = searchMemories(query: "recent context active goals", context: context, limit: 3)
        let stylePrefs = approvedStylePrefs(context: context)
        let instructions = personaStore.systemInstructions(
            persona: persona,
            topMemories: recent,
            stylePrefs: stylePrefs,
            condensedSummary: condensedSummary
        )
        let tools = buildTools(
            container: container,
            onEvent: makeEventHandler(),
            selecting: attachedToolNames
        )
#if FM_PCC
        // Real per-tier binding (iOS 27 SDK): on-device ↔ Private Cloud Compute.
        session = LanguageModelSession(model: model(for: tier), tools: tools, instructions: instructions)
#else
        // iOS 26 SDK: only the on-device model exists. The router degrades any cloud tier to
        // on-device, so `tier` is on-device here and the transparency stays honest.
        session = LanguageModelSession(tools: tools, instructions: instructions)
#endif
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
        // An isolated profile (e.g. research) runs as a subagent: its turns are never
        // persisted to the main conversation, never fold into the main session's transcript,
        // and skip curation/suggestion/preference side-effects — the main chat stays pristine
        // while the mode is active (§Phase 6).
        if activeProfile.isolatesContext {
            try await runIsolatedTurn(text: text, continuation: continuation)
            return
        }

        persist(role: "user", content: text)
        usedTokens += budget.estimatedTokens(text)
        turnToolCalls = []
        lastTurnToolCalls = []

        // Route the turn (§Phase 4): pick the model tier from policy + token pressure (or the
        // test override), and budget against *that* tier's window. Pure policy — safe outside
        // the FM gate.
        let resolution = router.resolve(task: .chat, estimatedPromptTokens: usedTokens, forcing: forcedTier)
        lastResponseTier = resolution.boundTier

#if canImport(FoundationModels)
        let activeBudget = ContextBudget(contextSize: resolution.contextSize)

        // Dynamic tool selection (§Phase 2): grow the attached tool set only when this
        // turn plausibly needs a tool we haven't attached yet, then re-seat the session.
        let needed = attachedToolNames.union(
            ToolSelector.selectedToolNames(for: text, hasImage: hasImage)
        )
        let toolsChanged = needed != attachedToolNames
        // The router may have escalated this turn to a different tier than the live session
        // is bound to (e.g. on-device → PCC). Re-seat onto the resolved tier's model so the
        // turn actually runs where routing said it would (§Phase 4).
        let tierChanged = resolution.boundTier != sessionTier

        // Proactively summarise before we risk overflowing the window. Re-seating also
        // rebuilds the session, so fold a needed tool-set or tier change into the same rebuild.
        if activeBudget.shouldSummarize(usedTokens: usedTokens) || toolsChanged || tierChanged {
            attachedToolNames = needed
            await reseatWithSummary(tier: resolution.boundTier)
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
        maybeSuggestRoutines()
        maybeOfferPreference(for: text)
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

    /// Re-seat the main session with a condensed summary. Preserves the current tier unless
    /// the caller asks for a different one (a routed escalation/de-escalation).
    private func reseatWithSummary(tier: ModelTier? = nil) async {
        let summary = (try? await budget.summarize(messages: fetchRecentMessages(limit: 20))) ?? ""
        buildSession(condensedSummary: summary.isEmpty ? nil : summary, tier: tier ?? sessionTier)
    }

    /// Periodically propose routines from recurring patterns (§Phase 5). Like curation, this
    /// runs off the streaming path, self-limits, and never blocks the turn or surfaces
    /// failures — candidates land in the in-app suggestion inbox, never a push.
    private func maybeSuggestRoutines() {
        turnsSinceSuggestion += 1
        guard turnsSinceSuggestion >= Self.suggestionInterval else { return }
        turnsSinceSuggestion = 0
        let recent = fetchRecentMessages(limit: 16)
        let suggester = routineSuggester
        Task { @MainActor in
            await suggester.suggest(recentMessages: recent)
        }
    }

    /// Occasionally offer an A/B style choice for the turn just taken (§Phase 5). The learner
    /// enforces its own frequency cap, so this is safe to call every turn; the choice surfaces
    /// via `preferenceLearner.pendingChoice`, which the chat UI observes.
    private func maybeOfferPreference(for text: String) {
        let learner = preferenceLearner
        Task { @MainActor in
            await learner.maybeOffer(for: text)
        }
    }

    /// Re-seat the session so a freshly-recorded style preference takes effect immediately,
    /// preserving conversation continuity via the condensed summary (§Phase 5 acceptance:
    /// picks measurably shift response style).
    public func applyLearnedPreferences() async {
        await reseatWithSummary()
    }

    // MARK: - Dynamic Profiles (§Phase 6)

    /// Switch conversation modes. The default `.assistant` runs on the main session; an
    /// isolating profile like `.research` spins up a subagent session seeded with a *baton* —
    /// a condensed summary of the main chat — so the mode has the context it needs without
    /// dragging (or polluting) the full transcript. Returning to `.assistant` tears the
    /// subagent down, leaving the main conversation exactly as it was.
    public func activateProfile(_ profile: ConversationProfile) async {
        guard profile.id != activeProfile.id else { return }
        activeProfile = profile

        if profile.isolatesContext {
            // Baton-pass: hand the subagent a compact summary of the main conversation.
            let baton = (try? await budget.summarize(messages: fetchRecentMessages(limit: 12))) ?? ""
            researchBaton = baton.isEmpty ? nil : baton
            researchUsedTokens = 0
            buildResearchSession(baton: researchBaton)
        } else {
#if canImport(FoundationModels)
            researchSession = nil
#endif
            researchBaton = nil
            researchUsedTokens = 0
        }
    }

    private func buildResearchSession(baton: String?, tier: ModelTier = .onDevice) {
        researchSessionTier = tier
#if canImport(FoundationModels)
        let context = ModelContext(container)
        let persona = personaStore.currentPersona()
        // A lean memory seed — research leans on the web-fetch tool and explicit recall, so
        // we keep the always-injected memory small to leave room for a deeper exchange.
        let recent = searchMemories(query: "recent context active goals", context: context, limit: 2)
        let instructions = personaStore.systemInstructions(
            persona: persona,
            topMemories: recent,
            stylePrefs: approvedStylePrefs(context: context),
            condensedSummary: baton,
            profileDelta: activeProfile.instructionDelta
        )
        let toolNames = activeProfile.restrictsToolsTo ?? ToolSelector.coreToolNames
        let tools = buildTools(container: container, onEvent: makeEventHandler(), selecting: toolNames)
#if FM_PCC
        researchSession = LanguageModelSession(model: model(for: tier), tools: tools, instructions: instructions)
#else
        researchSession = LanguageModelSession(tools: tools, instructions: instructions)
#endif
        researchUsedTokens = budget.estimatedTokens(instructions)
        researchSession?.prewarm()
#endif
    }

    /// Run one turn in the isolated subagent. Mirrors the main streaming path (routing,
    /// budget, typed overflow recovery) but persists nothing to the main conversation and
    /// fires none of the background passes — the isolation that keeps the main chat clean.
    private func runIsolatedTurn(
        text: String,
        continuation: AsyncThrowingStream<String, Error>.Continuation
    ) async throws {
        researchUsedTokens += budget.estimatedTokens(text)
        turnToolCalls = []
        lastTurnToolCalls = []

        let resolution = router.resolve(task: .reasoning, estimatedPromptTokens: researchUsedTokens)
        lastResponseTier = resolution.boundTier

#if canImport(FoundationModels)
        let activeBudget = ContextBudget(contextSize: resolution.contextSize)
        if researchSession == nil
            || activeBudget.shouldSummarize(usedTokens: researchUsedTokens)
            || resolution.boundTier != researchSessionTier {
            // Rebuild the subagent from the same baton, dropping its accumulated transcript,
            // and bind it to the tier this turn routed to (research prefers PCC, §Phase 4/6).
            researchUsedTokens = 0
            buildResearchSession(baton: researchBaton, tier: resolution.boundTier)
        }

        guard let researchSession else { throw AgentError.sessionNotInitialized }
        var finalText = ""
        do {
            finalText = try await stream(session: researchSession, text: text, continuation: continuation)
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            researchUsedTokens = 0
            buildResearchSession(baton: researchBaton, tier: resolution.boundTier)
            guard let retry = self.researchSession else { throw AgentError.sessionNotInitialized }
            finalText = try await stream(session: retry, text: text, continuation: continuation)
        }
        researchUsedTokens += budget.estimatedTokens(finalText)
        lastTurnToolCalls = turnToolCalls
#else
        let stub = "⚠️ Foundation Models is not available in this build. Run on a device with Apple Intelligence enabled."
        continuation.yield(stub)
#endif
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
