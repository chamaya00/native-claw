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
