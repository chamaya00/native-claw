import Foundation

#if canImport(FoundationModels)

/// Dynamic tool selection (IMPLEMENTATION_PLAN §Phase 2).
///
/// Tool definitions cost tokens, and at a fixed 4096-token window every definition we
/// attach is room taken from memory + transcript. So instead of handing the model every
/// tool each turn, this lightweight pre-step picks only the tools plausibly relevant to
/// the user's input. Memory tools stay always-on (the product is built on recall); the
/// rest are matched by cheap keyword heuristics. This is the precursor to Phase 6's
/// Dynamic Profiles, which replace the heuristic with a first-class declarative API.
public enum ToolSelector {

    /// Always attached — recall is core to the assistant, and these are inexpensive.
    public static let coreToolNames: Set<String> = [
        SearchMemoryTool.toolName,
        SaveMemoryNoteTool.toolName,
        ReadPersonaTool.toolName
    ]

    private struct Rule {
        let tool: String
        let keywords: [String]
    }

    private static let rules: [Rule] = [
        Rule(tool: ReadCalendarTool.toolName,
             keywords: ["calendar", "schedule", "agenda", "event", "meeting", "appointment",
                        "free", "busy", "today", "tomorrow", "week", "what's on"]),
        Rule(tool: CreateCalendarEventTool.toolName,
             keywords: ["calendar", "event", "meeting", "appointment", "schedule", "book",
                        "invite", "add to my calendar"]),
        Rule(tool: CreateReminderTool.toolName,
             keywords: ["remind", "reminder", "todo", "to-do", "to do", "don't forget",
                        "remember to", "task"]),
        Rule(tool: LookupContactTool.toolName,
             keywords: ["contact", "number", "phone", "email", "call", "text", "reach",
                        "who is", "address of"]),
        Rule(tool: WebFetchTool.toolName,
             keywords: ["http://", "https://", "www.", "website", "web page", "link",
                        "fetch", "open the", "url"]),
        Rule(tool: MapLookupTool.toolName,
             keywords: ["near", "nearby", "directions", "map", "restaurant", "coffee",
                        "store", "where is", "location of", "pharmacy", "gas"]),
        Rule(tool: ProposePersonaUpdateTool.toolName,
             keywords: ["be more", "be less", "from now on", "your vibe", "your tone",
                        "personality", "act like", "stop being"]),
        Rule(tool: ListImportedFilesTool.toolName,
             keywords: ["file", "document", "pdf", "imported", "attachment", "uploaded"]),
        Rule(tool: ReadImportedFileTool.toolName,
             keywords: ["file", "document", "pdf", "the doc", "that file", "read the"]),
        Rule(tool: UpdateMemoryNoteTool.toolName,
             keywords: ["update memory", "change what you", "correct that", "that's wrong",
                        "edit the note", "fix the memory"])
    ]

    /// Returns the set of tool names to attach for this input: the always-on core plus
    /// any tools whose keywords appear. An image attachment biases toward the tools that
    /// act on extracted content (calendar/reminder) since "add this from the screenshot"
    /// is the canonical multimodal flow.
    public static func selectedToolNames(for input: String, hasImage: Bool = false) -> Set<String> {
        let lower = input.lowercased()
        var selected = coreToolNames
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            selected.insert(rule.tool)
        }
        if hasImage {
            selected.insert(CreateCalendarEventTool.toolName)
            selected.insert(CreateReminderTool.toolName)
        }
        return selected
    }
}

#endif
