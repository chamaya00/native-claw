import Foundation

/// A conversation **mode** — the realisation of Dynamic Profiles (§Phase 6).
///
/// A profile bundles the three things that define how a turn runs: the *instructions* that
/// shape the model's behaviour, the *tools* it may reach for, and whether the mode runs in
/// an *isolated context* (a subagent) so focused work doesn't pollute the main chat. The
/// `ConversationEngine` applies a profile by re-seating the relevant session — switching
/// modes without losing the main conversation.
///
/// **Framework seam (and a §D deviation).** The plan names the WWDC26 `DynamicProfile`
/// protocol (a `body` returning a `Profile` of instructions + tools, with built-in
/// transcript trim/summarise + KV caching). That surface can't be compile-verified without
/// a device, so we model the *same behaviour* with this value type and the engine's existing
/// re-seat + `ContextBudget` machinery. Because a profile is fundamentally session-bound, it
/// lives in `AgentKit` alongside the engine rather than in `SkillsKit` as §D sketches —
/// `SkillsKit` owns the declarative-skill/App-Intents half of Phase 6. Adopting the real
/// `DynamicProfile` API later is a localised change behind this type.
public struct ConversationProfile: Sendable, Equatable, Identifiable {
    public let id: String
    public let displayName: String
    public let systemImage: String
    /// Extra instructions layered onto the session for this mode. Empty for the default
    /// assistant (its instructions are the persona).
    public let instructionDelta: String
    /// When non-nil, the mode is restricted to exactly these tool names (a tighter,
    /// purpose-built set than the default dynamic selection). Tool identifiers are stable
    /// schema strings (see `ToolSelector`), so the literals here are a deliberate contract.
    public let restrictsToolsTo: Set<String>?
    /// When true, the mode runs in its own session and its turns are **not** persisted to
    /// the main conversation or folded into the main session's transcript — a subagent. The
    /// main chat is untouched while the mode is active (§Phase 6 acceptance: "a 'research'
    /// profile runs without polluting the main chat context").
    public let isolatesContext: Bool

    public init(
        id: String,
        displayName: String,
        systemImage: String,
        instructionDelta: String,
        restrictsToolsTo: Set<String>?,
        isolatesContext: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.systemImage = systemImage
        self.instructionDelta = instructionDelta
        self.restrictsToolsTo = restrictsToolsTo
        self.isolatesContext = isolatesContext
    }

    /// The default mode: the full persona, dynamic tool selection, the durable transcript.
    public static let assistant = ConversationProfile(
        id: "assistant",
        displayName: "Assistant",
        systemImage: "bubble.left.and.bubble.right",
        instructionDelta: "",
        restrictsToolsTo: nil,
        isolatesContext: false
    )

    /// A focused research subagent: a tight instruction set, only the tools research needs
    /// (memory recall + web fetch), and an isolated context so an exploratory thread never
    /// clutters the main conversation. This is the framework's "phone-a-friend"/"baton-pass"
    /// pattern — the engine hands a condensed summary of the main chat in as context, then
    /// runs the research turns separately.
    public static let research = ConversationProfile(
        id: "research",
        displayName: "Research",
        systemImage: "magnifyingglass",
        instructionDelta: """
        You are in focused research mode. Dig into the user's question methodically: gather \
        what's relevant, reason step by step, and give a structured, well-sourced answer. \
        Prefer depth over brevity here. Use the web-fetch tool to consult a page when the \
        user gives a link or a fact needs checking, and recall what you already know about \
        them from memory. Stay on the research task.
        """,
        // Stable tool identifiers (see ToolSelector / *Tool.toolName). Memory recall +
        // persona read keep the answer grounded; web fetch is research's primary tool.
        restrictsToolsTo: ["searchMemory", "saveMemoryNote", "readPersona", "fetchWebPage"],
        isolatesContext: true
    )

    public static let all: [ConversationProfile] = [.assistant, .research]
}
