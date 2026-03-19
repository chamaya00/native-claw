import Foundation
import SwiftData

#if canImport(FoundationModels)
import FoundationModels

// MARK: - 1. searchMemory

struct SearchMemoryTool: Tool {
    static let name = "searchMemory"
    let name = SearchMemoryTool.name
    let description = "Search saved memory notes for relevant context. Use this proactively before answering questions about the user's interests, goals, or past conversations."

    @Generable
    struct Arguments {
        @Guide(description: "The search query to find relevant memory notes")
        var query: String
    }

    let container: ModelContainer
    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Searching memory…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let results = try await MainActor.run {
            let context = ModelContext(container)
            return searchMemories(query: arguments.query, context: context, limit: 5)
        }

        if results.isEmpty {
            return "No memory notes found matching '\(arguments.query)'."
        }

        let formatted = results.map { note in
            """
            - ID: \(note.id)
              Title: \(note.title)
              Summary: \(note.summary)
              Topics: \(note.topics.joined(separator: ", "))
              Created: \(note.createdAt.formatted(date: .abbreviated, time: .omitted))
            """
        }.joined(separator: "\n")

        return "Memory search results for '\(arguments.query)':\n\(formatted)"
    }
}

// MARK: - 2. saveMemoryNote

struct SaveMemoryNoteTool: Tool {
    static let name = "saveMemoryNote"
    let name = SaveMemoryNoteTool.name
    let description = "Propose saving a synthesized insight to memory. The user must confirm before it is written. Use for genuinely valuable, durable takeaways — not raw quotes."

    @Generable
    struct Arguments {
        @Guide(description: "A concise, descriptive title for this memory note")
        var title: String

        @Guide(description: "A synthesized insight or takeaway — not a raw quote. Should be useful standalone context.")
        var summary: String

        @Guide(description: "Relevant topic tags for this memory", .maximumCount(5))
        var topics: [String]

        @Guide(description: "Importance score from 0.0 (low) to 1.0 (high). Use 0.9 for critical facts, 0.5 for useful context, 0.2 for minor details.")
        var importanceScore: Float

        @Guide(description: "Optional source label, e.g. article title or conversation date")
        var sourceLabel: String
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        let draft = MemoryNoteDraft(
            title: arguments.title,
            summary: arguments.summary,
            topics: arguments.topics,
            importanceScore: arguments.importanceScore,
            sourceLabel: arguments.sourceLabel.isEmpty ? nil : arguments.sourceLabel
        )
        await onEvent(.pendingMemoryNote(draft))

        return """
        Memory note proposal ready for confirmation.
        Title: \(draft.title)
        Summary: \(draft.summary)
        Topics: \(draft.topics.joined(separator: ", "))
        A confirmation card will appear in the chat. Let the user know they can save or discard it.
        """
    }
}

// MARK: - 3. updateMemoryNote

struct UpdateMemoryNoteTool: Tool {
    static let name = "updateMemoryNote"
    let name = UpdateMemoryNoteTool.name
    let description = "Propose updating an existing memory note with refined information. The user must confirm before changes are written."

    @Generable
    struct Arguments {
        @Guide(description: "The UUID of the memory note to update")
        var id: String

        @Guide(description: "Proposed new title, or empty string to keep existing")
        var proposedTitle: String

        @Guide(description: "Proposed new summary, or empty string to keep existing")
        var proposedSummary: String

        @Guide(description: "Proposed new topics, or empty array to keep existing", .maximumCount(5))
        var proposedTopics: [String]

        @Guide(description: "Proposed new importance score (0.0–1.0), or -1.0 to keep existing")
        var proposedImportanceScore: Float
    }

    let container: ModelContainer
    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        guard let noteID = UUID(uuidString: arguments.id) else {
            return "Error: invalid UUID '\(arguments.id)'."
        }

        let originalTitle: String = try await MainActor.run {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<MemoryNote>(
                predicate: #Predicate { $0.id == noteID }
            )
            return (try? context.fetch(descriptor))?.first?.title ?? "Unknown"
        }

        let draft = MemoryUpdateDraft(
            noteID: noteID,
            originalTitle: originalTitle,
            proposedTitle: arguments.proposedTitle.isEmpty ? nil : arguments.proposedTitle,
            proposedSummary: arguments.proposedSummary.isEmpty ? nil : arguments.proposedSummary,
            proposedTopics: arguments.proposedTopics.isEmpty ? nil : arguments.proposedTopics,
            proposedImportanceScore: arguments.proposedImportanceScore < 0 ? nil : arguments.proposedImportanceScore
        )
        await onEvent(.pendingMemoryUpdate(draft))

        return """
        Memory update proposal ready for confirmation.
        Note: \(originalTitle) (ID: \(arguments.id))
        A confirmation card will appear in the chat.
        """
    }
}

// MARK: - 4. readPersona

struct ReadPersonaTool: Tool {
    static let name = "readPersona"
    let name = ReadPersonaTool.name
    let description = "Read the current Claw persona — name, purpose, tone, values, and expertise areas."

    @Generable
    struct Arguments {
        @Guide(description: "Pass 'read' to fetch the current persona")
        var action: String
    }

    let container: ModelContainer
    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Reading persona…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let result: String = try await MainActor.run {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Persona>()
            guard let persona = (try? context.fetch(descriptor))?.first else {
                return "No persona configured yet."
            }
            return """
            Name: \(persona.name)
            Purpose: \(persona.purpose)
            Tone: \(persona.tone)
            Values: \(persona.values.joined(separator: ", "))
            Expertise areas: \(persona.expertiseAreas.joined(separator: ", "))
            """
        }
        return result
    }
}

// MARK: - 5. proposePersonaUpdate

struct ProposePersonaUpdateTool: Tool {
    static let name = "proposePersonaUpdate"
    let name = ProposePersonaUpdateTool.name
    let description = "Propose updating the Claw persona. Use when the user says 'be more concise', 'focus on X', or requests a personality change. User must confirm."

    @Generable
    struct Arguments {
        @Guide(description: "Proposed new purpose, or empty string to keep existing")
        var proposedPurpose: String

        @Guide(description: "Proposed new tone, or empty string to keep existing")
        var proposedTone: String

        @Guide(description: "Proposed new values list, or empty array to keep existing", .maximumCount(5))
        var proposedValues: [String]

        @Guide(description: "Proposed new expertise areas, or empty array to keep existing", .maximumCount(8))
        var proposedExpertiseAreas: [String]
    }

    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        let draft = PersonaUpdateDraft(
            proposedPurpose: arguments.proposedPurpose.isEmpty ? nil : arguments.proposedPurpose,
            proposedTone: arguments.proposedTone.isEmpty ? nil : arguments.proposedTone,
            proposedValues: arguments.proposedValues.isEmpty ? nil : arguments.proposedValues,
            proposedExpertiseAreas: arguments.proposedExpertiseAreas.isEmpty ? nil : arguments.proposedExpertiseAreas
        )
        await onEvent(.pendingPersonaUpdate(draft))

        return """
        Persona update proposal ready for confirmation.
        A confirmation card will appear in the chat.
        """
    }
}

// MARK: - 6. listImportedFiles

struct ListImportedFilesTool: Tool {
    static let name = "listImportedFiles"
    let name = ListImportedFilesTool.name
    let description = "List all files the user has imported. Use to discover what context files are available before referencing them."

    @Generable
    struct Arguments {
        @Guide(description: "Pass 'list' to retrieve all imported files")
        var action: String
    }

    let container: ModelContainer
    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        await onEvent(.toolStarted("Listing files…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let result: String = try await MainActor.run {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImportedFile>(
                sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
            )
            let files = (try? context.fetch(descriptor)) ?? []
            if files.isEmpty {
                return "No files imported yet."
            }
            return files.map { file in
                "- ID: \(file.id)\n  Name: \(file.filename)\n  Imported: \(file.importedAt.formatted(date: .abbreviated, time: .omitted))\n  Preview: \(file.contentPreview.prefix(100))…"
            }.joined(separator: "\n")
        }
        return result
    }
}

// MARK: - 7. readImportedFile

struct ReadImportedFileTool: Tool {
    static let name = "readImportedFile"
    let name = ReadImportedFileTool.name
    let description = "Read the full text content of an imported file by its ID. Use when the user references a file or when a file is clearly relevant to their question."

    private static let maxChars = 4000

    @Generable
    struct Arguments {
        @Guide(description: "The UUID of the imported file to read")
        var id: String
    }

    let container: ModelContainer
    let onEvent: @MainActor @Sendable (ToolEvent) -> Void

    func call(arguments: Arguments) async throws -> String {
        guard let fileID = UUID(uuidString: arguments.id) else {
            return "Error: invalid UUID '\(arguments.id)'."
        }

        await onEvent(.toolStarted("Reading file…"))
        defer { Task { await onEvent(.toolCompleted) } }

        let result: String = try await MainActor.run {
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<ImportedFile>(
                predicate: #Predicate { $0.id == fileID }
            )
            guard let file = (try? context.fetch(descriptor))?.first else {
                return "File not found with ID \(arguments.id)."
            }
            // Update last accessed
            file.lastAccessedAt = .now
            try? context.save()

            let text = file.fullText
            if text.count > Self.maxChars {
                let truncated = String(text.prefix(Self.maxChars))
                return "Filename: \(file.filename)\n[TRUNCATED — showing first \(Self.maxChars) of \(text.count) chars]\n\n\(truncated)"
            }
            return "Filename: \(file.filename)\n\n\(text)"
        }
        return result
    }
}

// MARK: - Helper: memory text search

func searchMemories(query: String, context: ModelContext, limit: Int) -> [MemoryNote] {
    let descriptor = FetchDescriptor<MemoryNote>(
        predicate: #Predicate { $0.isUserApproved == true },
        sortBy: [
            SortDescriptor(\.importanceScore, order: .reverse),
            SortDescriptor(\.updatedAt, order: .reverse)
        ]
    )
    let all = (try? context.fetch(descriptor)) ?? []
    let lower = query.lowercased()
    let terms = lower.split(separator: " ").map(String.init)

    func score(_ note: MemoryNote) -> Int {
        var s = 0
        for term in terms {
            if note.title.lowercased().contains(term) { s += 3 }
            if note.summary.lowercased().contains(term) { s += 2 }
            for topic in note.topics where topic.lowercased().contains(term) { s += 1 }
        }
        return s
    }

    let scored = all.map { ($0, score($0)) }.filter { $0.1 > 0 || terms.isEmpty }
    let sorted = scored.sorted { $0.1 > $1.1 }
    return Array(sorted.prefix(limit).map(\.0))
}

// MARK: - Onboarding PersonaDraft (@Generable for structured extraction)

@Generable
struct PersonaDraft {
    @Guide(description: "What the user wants Claw to help with — their main goal or use case")
    var purpose: String

    @Guide(description: "The desired tone and communication style, e.g. 'direct and sharp' or 'warm and encouraging'")
    var tone: String

    @Guide(description: "Core values that should guide responses, e.g. 'concise', 'honest', 'synthesis-focused'", .maximumCount(5))
    var values: [String]

    @Guide(description: "Topics the user cares about most right now", .maximumCount(8))
    var expertiseAreas: [String]
}

// MARK: - Tool collection builder

func buildTools(
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
        ReadImportedFileTool(container: container, onEvent: onEvent)
    ]
}

#else

// MARK: - Stub search (available without FoundationModels for tests)

func searchMemories(query: String, context: ModelContext, limit: Int) -> [MemoryNote] {
    let descriptor = FetchDescriptor<MemoryNote>(
        predicate: #Predicate { $0.isUserApproved == true },
        sortBy: [SortDescriptor(\.importanceScore, order: .reverse)]
    )
    let all = (try? context.fetch(descriptor)) ?? []
    let lower = query.lowercased()
    let terms = lower.split(separator: " ").map(String.init)

    func score(_ note: MemoryNote) -> Int {
        var s = 0
        for term in terms {
            if note.title.lowercased().contains(term) { s += 3 }
            if note.summary.lowercased().contains(term) { s += 2 }
            for topic in note.topics where topic.lowercased().contains(term) { s += 1 }
        }
        return s
    }

    let scored = all.map { ($0, score($0)) }.filter { $0.1 > 0 || terms.isEmpty }
    return Array(scored.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0))
}

#endif
