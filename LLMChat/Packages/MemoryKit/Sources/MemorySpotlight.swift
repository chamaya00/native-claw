import Foundation
import SwiftData

#if canImport(AppIntents) && canImport(CoreSpotlight)
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Memory as a system-native, attributable entity (§Phase 3)
//
// Rather than build a custom vector store (explicitly on the §B DO-NOT list), we
// contribute the user's memory to the **Spotlight semantic index via App Intents
// entity schemas**. The payoff is threefold: retrieval is maintained by Apple, it's
// attributable (results link back to a real entity), and the same schema makes memory
// reachable by Spotlight, Siri, and Shortcuts for free. Only *approved* facts are
// indexed — the review queue never reaches the system index.

/// A memory fact exposed to the system. Backed 1:1 by an approved `MemoryNote`.
@available(iOS 18.0, *)
public struct MemoryFactEntity: IndexedEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Memory")
    }

    public static var defaultQuery: MemoryFactQuery { MemoryFactQuery() }

    public var id: UUID

    @Property(title: "Title")
    public var title: String

    @Property(title: "Summary")
    public var summary: String

    public var topics: [String]

    public init(id: UUID, title: String, summary: String, topics: [String]) {
        // Assign the plain stored properties (`id`, `topics`) before the
        // `@Property`-wrapped ones. The AppIntents `@Property` setter accesses
        // `self`, so Swift's definite-initialization requires every non-wrapped
        // stored property to be initialized first — otherwise the wrapped
        // assignment trips "variable 'self.topics' used before being initialized".
        self.id = id
        self.topics = topics
        self.title = title
        self.summary = summary
    }

    public init(note: MemoryNote) {
        self.init(id: note.id, title: note.title, summary: note.summary, topics: note.topics)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(summary)")
    }

    /// Drives what Spotlight indexes and ranks. Topics become keywords so semantic
    /// matches on related terms still surface the fact.
    public var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = title
        attrs.contentDescription = summary
        attrs.keywords = topics
        attrs.displayName = title
        return attrs
    }
}

/// Resolves `MemoryFactEntity`s from the SwiftData store for the system to query.
@available(iOS 18.0, *)
public struct MemoryFactQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [MemoryFactEntity] {
        await MemoryEntityBridge.entities(for: identifiers)
    }

    public func suggestedEntities() async throws -> [MemoryFactEntity] {
        await MemoryEntityBridge.allApprovedEntities(limit: 25)
    }
}

/// App Intents queries are instantiated by the system, so they can't receive the app's
/// injected `ModelContainer`. This bridge holds the container the app registers at
/// launch and runs the actual fetches against it.
public enum MemoryEntityBridge {
    @MainActor private static var container: ModelContainer?

    @MainActor
    public static func register(container: ModelContainer) {
        self.container = container
    }

    @available(iOS 18.0, *)
    @MainActor
    static func entities(for identifiers: [UUID]) -> [MemoryFactEntity] {
        guard let container else { return [] }
        let context = ModelContext(container)
        let ids = Set(identifiers)
        let descriptor = FetchDescriptor<MemoryNote>(
            predicate: #Predicate { $0.isUserApproved == true && ids.contains($0.id) }
        )
        return ((try? context.fetch(descriptor)) ?? []).map(MemoryFactEntity.init(note:))
    }

    @available(iOS 18.0, *)
    @MainActor
    static func allApprovedEntities(limit: Int) -> [MemoryFactEntity] {
        guard let container else { return [] }
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<MemoryNote>(
            predicate: #Predicate { $0.isUserApproved == true },
            sortBy: [SortDescriptor(\.importanceScore, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).map(MemoryFactEntity.init(note:))
    }
}

// MARK: - Spotlight index maintenance

/// Keeps the Spotlight index in step with the memory store: approved facts are donated,
/// edited facts re-donated, deleted/unapproved facts removed. Call these wherever a
/// `MemoryNote`'s approved state or content changes.
public enum MemorySpotlightIndexer {
    public static let domain = "com.charlesamaya.llmchat.memory"

    /// Donate (or refresh) a single approved fact. No-op for unapproved candidates so the
    /// review queue never leaks into the system index.
    public static func index(_ note: MemoryNote) {
        guard #available(iOS 18.0, *), note.isUserApproved else { return }
        let entity = MemoryFactEntity(note: note)
        let item = CSSearchableItem(
            uniqueIdentifier: note.id.uuidString,
            domainIdentifier: domain,
            attributeSet: entity.attributeSet
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    public static func remove(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])
    }

    /// Rebuild the index from the store — used after a bulk change (e.g. "forget me",
    /// first launch after enabling CloudKit, or a sync pulling facts from another device).
    @MainActor
    public static func reindexAll(container: ModelContainer) {
        guard #available(iOS 18.0, *) else { return }
        let context = ModelContext(container)
        let approved = (try? context.fetch(
            FetchDescriptor<MemoryNote>(predicate: #Predicate { $0.isUserApproved == true })
        )) ?? []
        // Build items on the MainActor up front, then issue the two index operations
        // without nesting model objects (or non-Sendable items) inside a completion
        // closure. CoreSpotlight serialises a client's batched operations in submission
        // order, so the delete lands before the re-index.
        let items = approved.map { note in
            CSSearchableItem(
                uniqueIdentifier: note.id.uuidString,
                domainIdentifier: domain,
                attributeSet: MemoryFactEntity(note: note).attributeSet
            )
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !items.isEmpty else { return }
        index.indexSearchableItems(items)
    }
}

#else

// Toolchains without AppIntents/CoreSpotlight (older SDKs, some simulators): no-op
// indexer so call sites compile unchanged.
public enum MemorySpotlightIndexer {
    public static func index(_ note: MemoryNote) {}
    public static func remove(id: UUID) {}
    @MainActor public static func reindexAll(container: ModelContainer) {}
}

public enum MemoryEntityBridge {
    @MainActor public static func register(container: ModelContainer) {}
}

#endif
