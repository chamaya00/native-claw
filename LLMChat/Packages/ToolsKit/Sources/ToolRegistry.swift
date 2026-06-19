import Foundation
import SwiftData
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

/// Assembles the tool set attached to a `LanguageModelSession`.
///
/// `selecting` is the dynamic tool-selection seam (§Phase 2): pass the names returned
/// by `ToolSelector` to attach only the tools plausibly relevant to the turn — fewer
/// tool definitions means more of the 4K window for memory and transcript. Pass `nil`
/// to attach the full set (used where selection doesn't apply).
public func buildTools(
    container: ModelContainer,
    onEvent: @escaping @MainActor @Sendable (ToolEvent) -> Void,
    selecting: Set<String>? = nil
) -> [any Tool] {
    let all: [any Tool] = [
        SearchMemoryTool(container: container, onEvent: onEvent),
        SaveMemoryNoteTool(onEvent: onEvent),
        UpdateMemoryNoteTool(container: container, onEvent: onEvent),
        ReadPersonaTool(container: container, onEvent: onEvent),
        ProposePersonaUpdateTool(onEvent: onEvent),
        ListImportedFilesTool(container: container, onEvent: onEvent),
        ReadImportedFileTool(container: container, onEvent: onEvent),
        CreateReminderTool(onEvent: onEvent),
        ReadCalendarTool(onEvent: onEvent),
        CreateCalendarEventTool(onEvent: onEvent),
        LookupContactTool(onEvent: onEvent),
        WebFetchTool(onEvent: onEvent),
        MapLookupTool(onEvent: onEvent)
    ]
    guard let selecting else { return all }
    return all.filter { selecting.contains($0.name) }
}

#endif
