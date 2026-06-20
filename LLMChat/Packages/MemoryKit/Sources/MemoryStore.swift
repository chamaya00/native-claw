import Foundation
import SwiftData

/// Local retrieval over saved `MemoryNote`s.
///
/// Phase 1 uses a lightweight scored text match. Phase 3 replaces this with the
/// FoundationModels Spotlight-powered search tool + App Intents entity schemas
/// (see IMPLEMENTATION_PLAN §Phase 3) — the call site here is the seam for that swap.
public func searchMemories(query: String, context: ModelContext, limit: Int) -> [MemoryNote] {
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

// MARK: - Curation review inbox (Phase 3)

/// Facts the curation pass proposed but the user hasn't acted on yet. Surfaced in the
/// memory browser's review section; never injected into prompts or indexed in Spotlight.
@MainActor
public func pendingCuratedNotes(context: ModelContext) -> [MemoryNote] {
    let descriptor = FetchDescriptor<MemoryNote>(
        predicate: #Predicate { $0.isUserApproved == false },
        sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
    )
    return (try? context.fetch(descriptor)) ?? []
}

/// Approve a curated candidate (or any unapproved note): it becomes part of memory and
/// is donated to the Spotlight index so the system can retrieve it.
@MainActor
public func approveNote(_ note: MemoryNote, context: ModelContext) {
    note.isUserApproved = true
    note.updatedAt = .now
    try? context.save()
    MemorySpotlightIndexer.index(note)
}

/// Edit an approved fact in place and refresh its Spotlight entry.
@MainActor
public func updateNote(
    _ note: MemoryNote,
    title: String,
    summary: String,
    topics: [String],
    importance: Float,
    context: ModelContext
) {
    note.title = title
    note.summary = summary
    note.topics = topics
    note.importanceScore = importance
    note.updatedAt = .now
    try? context.save()
    if note.isUserApproved {
        MemorySpotlightIndexer.index(note)
    }
}

/// Delete a single fact and pull it from the Spotlight index.
@MainActor
public func deleteNote(_ note: MemoryNote, context: ModelContext) {
    let id = note.id
    context.delete(note)
    try? context.save()
    MemorySpotlightIndexer.remove(id: id)
}

/// "Forget me": delete every stored fact and clear the Spotlight index. The hard
/// privacy guarantee that the memory is genuinely the user's to revoke (§Phase 3).
@MainActor
public func forgetAllMemory(context: ModelContext) {
    let all = (try? context.fetch(FetchDescriptor<MemoryNote>())) ?? []
    let ids = all.map(\.id)
    for note in all { context.delete(note) }
    try? context.save()
    for id in ids { MemorySpotlightIndexer.remove(id: id) }
}
