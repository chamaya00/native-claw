import Foundation
import SwiftData
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels

/// Assembles the tool set attached to a `LanguageModelSession`.
///
/// Phase 2 will add dynamic tool *selection* (only attach tools plausibly relevant
/// to the turn, to buy back context budget). For Phase 1 the full set is attached;
/// this function is the single seam where that selection logic will live.
public func buildTools(
    container: ModelContainer,
    onEvent: @escaping @MainActor @Sendable (ToolEvent) -> Void
) -> [any Tool] {
    [
        SearchMemoryTool(container: container, onEvent: onEvent),
        SaveMemoryNoteTool(onEvent: onEvent),
        UpdateMemoryNoteTool(container: container, onEvent: onEvent),
        ReadPersonaTool(container: container, onEvent: onEvent),
        ProposePersonaUpdateTool(onEvent: onEvent),
        ListImportedFilesTool(container: container, onEvent: onEvent),
        ReadImportedFileTool(container: container, onEvent: onEvent),
        CreateReminderTool(onEvent: onEvent)
    ]
}

#endif
