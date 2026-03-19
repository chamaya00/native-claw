import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Errors

enum AgentError: LocalizedError {
    case modelUnavailable(String)
    case sessionNotInitialized
    case noPersona

    var errorDescription: String? {
        switch self {
        case .modelUnavailable(let reason):
            return "Apple Intelligence is not available: \(reason). Ensure your device supports Apple Intelligence and it is enabled in Settings."
        case .sessionNotInitialized:
            return "Session not initialized. Please restart the app."
        case .noPersona:
            return "No persona found. Please complete onboarding."
        }
    }
}

// MARK: - AgentService

@Observable
@MainActor
final class AgentService {

    // MARK: State

    var isAvailable: Bool = false
    var toolIndicator: String?

    // Pending confirmations — set by tools, cleared after user acts
    var pendingMemoryNote: MemoryNoteDraft?
    var pendingMemoryUpdate: MemoryUpdateDraft?
    var pendingPersonaUpdate: PersonaUpdateDraft?

    // MARK: Private

    private let container: ModelContainer

#if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var onboardingSession: LanguageModelSession?
#endif

    // MARK: Init

    init(container: ModelContainer) {
        self.container = container
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        if case .available = model.availability {
            isAvailable = true
        }
#endif
    }

    // MARK: - Session Initialization

    func initializeSession() async throws {
#if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        switch model.availability {
        case .unavailable(let reason):
            throw AgentError.modelUnavailable(String(describing: reason))
        case .available:
            break
        }

        let context = ModelContext(container)

        // Read persona for system prompt injection
        let persona = (try? context.fetch(FetchDescriptor<Persona>()))?.first

        // Inject top 3 recent memories as background context
        let recentMemories = searchMemories(
            query: "recent context active goals",
            context: context,
            limit: 3
        )

        let systemPrompt = buildSystemPrompt(persona: persona, topMemories: recentMemories)
        let tools = buildTools(container: container, onEvent: handleToolEvent)

        session = LanguageModelSession(
            tools: tools,
            instructions: systemPrompt
        )
#else
        isAvailable = false
#endif
    }

    func invalidateSession() {
#if canImport(FoundationModels)
        session = nil
        onboardingSession = nil
#endif
        pendingMemoryNote = nil
        pendingMemoryUpdate = nil
        pendingPersonaUpdate = nil
    }

    // MARK: - Chat

    func respond(to text: String, toolCallsOut: inout [String]) async throws -> String {
#if canImport(FoundationModels)
        guard let session else {
            throw AgentError.sessionNotInitialized
        }
        do {
            let response = try await session.respond(to: text)
            return response.content
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Condense: recreate session with fresh context (transcript exceeded limit)
            // NOTE: per CLAUDE.md, we rebuild from persona + recent memories
            try await initializeSession()
            guard let newSession = self.session else { throw AgentError.sessionNotInitialized }
            let response = try await newSession.respond(to: text)
            return response.content
        }
#else
        return "⚠️ Foundation Models is not available on this device or simulator. Build and run on a real device with Apple Intelligence enabled."
#endif
    }

    // MARK: - Onboarding

    func initOnboardingSession() {
#if canImport(FoundationModels)
        let prompt = """
        You are setting up a private AI agent called Claw for a new user. \
        Your job is to learn three things through friendly conversation:
        1. What they want the agent to help them with (their main goal or use case)
        2. How they want the agent to communicate (tone and style)
        3. What topics they care most about right now

        Ask one question at a time. Be warm but concise. After gathering enough information \
        (usually 3–5 exchanges), summarize what you learned and ask the user to confirm.
        Do not use bullet points or headers. Keep your messages short.
        """
        onboardingSession = LanguageModelSession(instructions: prompt)
#endif
    }

    func onboardingRespond(to text: String) async throws -> String {
#if canImport(FoundationModels)
        guard let onboardingSession else {
            throw AgentError.sessionNotInitialized
        }
        let response = try await onboardingSession.respond(to: text)
        return response.content
#else
        return "Foundation Models not available. Please run on a real device with Apple Intelligence."
#endif
    }

    /// Extract a structured PersonaDraft from the onboarding conversation.
    func extractPersonaDraft() async throws -> (purpose: String, tone: String, values: [String], expertiseAreas: [String]) {
#if canImport(FoundationModels)
        guard let onboardingSession else {
            throw AgentError.sessionNotInitialized
        }
        let response = try await onboardingSession.respond(
            to: "Based on our conversation, extract a structured persona definition.",
            generating: PersonaDraft.self
        )
        let draft = response.content
        return (draft.purpose, draft.tone, draft.values, draft.expertiseAreas)
#else
        return (
            purpose: "General AI assistance",
            tone: "Direct and helpful",
            values: ["concise", "honest"],
            expertiseAreas: ["productivity", "writing"]
        )
#endif
    }

    // MARK: - Confirmation Actions

    func confirmMemoryNote(_ draft: MemoryNoteDraft) throws {
        let context = ModelContext(container)
        let note = MemoryNote(
            title: draft.title,
            summary: draft.summary,
            sourceLabel: draft.sourceLabel,
            topics: draft.topics,
            importanceScore: draft.importanceScore,
            isUserApproved: true
        )
        context.insert(note)
        try context.save()
        pendingMemoryNote = nil
    }

    func discardMemoryNote() {
        pendingMemoryNote = nil
    }

    func confirmMemoryUpdate(_ draft: MemoryUpdateDraft) throws {
        let context = ModelContext(container)
        let id = draft.noteID
        let descriptor = FetchDescriptor<MemoryNote>(predicate: #Predicate { $0.id == id })
        guard let note = (try? context.fetch(descriptor))?.first else { return }

        if let t = draft.proposedTitle { note.title = t }
        if let s = draft.proposedSummary { note.summary = s }
        if let topics = draft.proposedTopics { note.topics = topics }
        if let score = draft.proposedImportanceScore { note.importanceScore = score }
        note.updatedAt = .now
        try context.save()
        pendingMemoryUpdate = nil
    }

    func discardMemoryUpdate() {
        pendingMemoryUpdate = nil
    }

    func confirmPersonaUpdate(_ draft: PersonaUpdateDraft) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Persona>()
        guard let persona = (try? context.fetch(descriptor))?.first else { return }

        if let p = draft.proposedPurpose { persona.purpose = p }
        if let t = draft.proposedTone { persona.tone = t }
        if let v = draft.proposedValues { persona.values = v }
        if let e = draft.proposedExpertiseAreas { persona.expertiseAreas = e }
        persona.updatedAt = .now
        try context.save()
        pendingPersonaUpdate = nil
    }

    func discardPersonaUpdate() {
        pendingPersonaUpdate = nil
    }

    // MARK: - Tool Event Handler

    private func handleToolEvent(_ event: ToolEvent) {
        switch event {
        case .toolStarted(let label):
            toolIndicator = label
        case .toolCompleted:
            toolIndicator = nil
        case .pendingMemoryNote(let draft):
            pendingMemoryNote = draft
        case .pendingMemoryUpdate(let draft):
            pendingMemoryUpdate = draft
        case .pendingPersonaUpdate(let draft):
            pendingPersonaUpdate = draft
        }
    }

    // MARK: - System Prompt Builder

    private func buildSystemPrompt(persona: Persona?, topMemories: [MemoryNote]) -> String {
        var prompt = """
        You are Claw, a private on-device AI agent. Your persona and purpose are defined in your memory files and loaded at the start of each session.

        Rules:
        - You have access to tools. Use them proactively when they would help you give a better answer.
        - Always search memory before answering questions about the user's interests, goals, or past conversations.
        - Never write to memory or update the persona without proposing the change first and getting user confirmation.
        - Prefer short, precise responses. No filler. No hedging.
        - If you cannot do something with your available tools, say so clearly and suggest what the user could do instead.
        - All processing is on-device and private. Never reference external services.
        """

        if let persona {
            prompt += """


            Your current persona:
            - Name: \(persona.name)
            - Purpose: \(persona.purpose)
            - Tone: \(persona.tone)
            - Values: \(persona.values.joined(separator: ", "))
            - Expertise areas: \(persona.expertiseAreas.joined(separator: ", "))
            """
        }

        if !topMemories.isEmpty {
            prompt += "\n\nRecent context from memory:\n"
            for memory in topMemories {
                prompt += "- \(memory.title): \(memory.summary)\n"
            }
        }

        return prompt
    }
}
