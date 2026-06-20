import Foundation
import SwiftData
import MemoryKit

#if canImport(AppIntents) && canImport(CoreSpotlight)
import AppIntents
import CoreSpotlight
import UniformTypeIdentifiers

// MARK: - Skills as system-native App Intents (§Phase 6)
//
// The plan models a skill as a **declarative composition of App Intents**, exposed through
// an `AppShortcutsProvider` and adopting App Intents schemas so skills are discoverable by
// Siri/Spotlight/Shortcuts — one abstraction, two payoffs (no SiriKit; §B DO-NOT). This is
// the same `IndexedEntity` + bridge pattern Phase 3 used for memory, so retrieval stays
// system-native and attributable, and the assistant's real actions are reachable OS-wide.
//
// **Schema seam.** Apple's App Intents *assistant schemas* (the `@AssistantIntent` /
// `@AssistantEntity` WWDC26 macros) can't be compile-verified without the matching SDK on a
// device, so this adopts the stable `AppEntity` / `AppIntent` / `IndexedEntity` surface
// (already proven in Phase 3) and leaves schema-macro adoption as a documented one-annotation
// change. Only **approved** skills are exposed — suggested/dismissed rows never reach the
// system index or the Shortcuts list.

/// An approved skill exposed to the system. Backed 1:1 by an approved `Skill`.
@available(iOS 18.0, *)
public struct SkillEntity: IndexedEntity {
    public static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Skill")
    }

    public static var defaultQuery: SkillQuery { SkillQuery() }

    public var id: UUID

    @Property(title: "Name")
    public var name: String

    @Property(title: "Summary")
    public var summary: String

    public init(id: UUID, name: String, summary: String) {
        // Plain stored properties before `@Property`-wrapped ones — the AppIntents setter
        // touches `self`, so definite-initialization requires `id` first (same constraint
        // documented in `MemoryFactEntity`).
        self.id = id
        self.name = name
        self.summary = summary
    }

    public init(skill: Skill) {
        self.init(id: skill.id, name: skill.name, summary: skill.summary)
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }

    /// Drives what Spotlight indexes and ranks for this skill (matches `MemoryFactEntity`).
    public var attributeSet: CSSearchableItemAttributeSet {
        let attrs = CSSearchableItemAttributeSet(contentType: .text)
        attrs.title = name
        attrs.contentDescription = summary
        attrs.displayName = name
        return attrs
    }
}

/// Resolves `SkillEntity`s from the store for the system to query. Only approved skills are
/// ever surfaced.
@available(iOS 18.0, *)
public struct SkillQuery: EntityQuery {
    public init() {}

    public func entities(for identifiers: [UUID]) async throws -> [SkillEntity] {
        await SkillEntityBridge.entities(for: identifiers)
    }

    public func suggestedEntities() async throws -> [SkillEntity] {
        await SkillEntityBridge.approvedEntities()
    }
}

/// Run an approved skill end-to-end from Siri/Spotlight/Shortcuts. The recipe is declarative
/// and read-only/approval-gated (see `SkillCatalog`), so invoking it from outside the app
/// never performs an unapproved mutation.
@available(iOS 18.0, *)
public struct RunSkillIntent: AppIntent {
    public static var title: LocalizedStringResource { "Run Skill" }
    public static var description: IntentDescription {
        IntentDescription("Runs one of your saved Claw skills and reports the result.")
    }

    @Parameter(title: "Skill")
    public var skill: SkillEntity

    public init() {}
    public init(skill: SkillEntity) { self.skill = skill }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = await SkillEntityBridge.run(skillID: skill.id)
        return .result(dialog: IntentDialog(stringLiteral: text))
    }
}

/// Exposes Claw's skills to Siri, Spotlight, and the Shortcuts app. Apps without an
/// `AppShortcutsProvider` are invisible to the new Siri (§Phase 7 note), so we register one
/// here; Phase 7 adds the voice/system-invocation surface on top of the same intents.
@available(iOS 18.0, *)
public struct ClawShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: RunSkillIntent(),
            phrases: [
                "Run a skill with \(.applicationName)",
                "Run my \(.applicationName) skill"
            ],
            shortTitle: "Run Skill",
            systemImageName: "wand.and.stars"
        )
    }
}

/// App Intents queries/intents are instantiated by the system, so they can't receive the
/// app's injected `ModelContainer`. This bridge holds the container the app registers at
/// launch and runs the fetches/execution against it — the same seam `MemoryEntityBridge`
/// uses for memory.
public enum SkillEntityBridge {
    @MainActor private static var container: ModelContainer?

    @MainActor
    public static func register(container: ModelContainer) {
        self.container = container
    }

    @available(iOS 18.0, *)
    @MainActor
    static func entities(for identifiers: [UUID]) -> [SkillEntity] {
        guard let container else { return [] }
        let ids = Set(identifiers)
        let context = ModelContext(container)
        return SkillStore.approved(context: context)
            .filter { ids.contains($0.id) }
            .map(SkillEntity.init(skill:))
    }

    @available(iOS 18.0, *)
    @MainActor
    static func approvedEntities() -> [SkillEntity] {
        guard let container else { return [] }
        let context = ModelContext(container)
        return SkillStore.approved(context: context).map(SkillEntity.init(skill:))
    }

    /// Resolve and run an approved skill by id, returning user-facing result text. Refuses to
    /// run anything not approved — approval is the structural gate for execution.
    @MainActor
    static func run(skillID: UUID) async -> String {
        guard let container else { return "Skills aren't ready yet." }
        let context = ModelContext(container)
        guard let skill = SkillStore.approved(context: context).first(where: { $0.id == skillID }) else {
            return "That skill isn't available."
        }
        let result = await SkillRunner(container: container).run(skill)
        return result.text
    }
}

// MARK: - Spotlight donation

/// Keeps the Spotlight index in step with approved skills so they're discoverable from the
/// system (the same maintenance contract as `MemorySpotlightIndexer`). Call on approve/edit/
/// dismiss/delete; `reindexAll` rebuilds after a bulk change or a cross-device sync.
public enum SkillSpotlightIndexer {
    public static let domain = "com.charlesamaya.llmchat.skills"

    /// Donate (or refresh) a single approved skill. No-op for suggested/dismissed rows so
    /// the inbox never leaks into the system index.
    public static func index(_ skill: Skill) {
        guard #available(iOS 18.0, *), skill.status == SkillStatus.approved.rawValue else { return }
        let item = CSSearchableItem(
            uniqueIdentifier: skill.id.uuidString,
            domainIdentifier: domain,
            attributeSet: SkillEntity(skill: skill).attributeSet
        )
        CSSearchableIndex.default().indexSearchableItems([item])
    }

    public static func remove(id: UUID) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [id.uuidString])
    }

    /// Rebuild the skills index from the store — used after a bulk change or a sync pulling
    /// skills from another device.
    @MainActor
    public static func reindexAll(container: ModelContainer) {
        guard #available(iOS 18.0, *) else { return }
        let context = ModelContext(container)
        let items = SkillStore.approved(context: context).map { skill in
            CSSearchableItem(
                uniqueIdentifier: skill.id.uuidString,
                domainIdentifier: domain,
                attributeSet: SkillEntity(skill: skill).attributeSet
            )
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain])
        guard !items.isEmpty else { return }
        index.indexSearchableItems(items)
    }
}

#else

// Toolchains without AppIntents (older SDKs / some simulators): no-op bridge + indexer so
// the app's launch-time registration and skill-store call sites compile unchanged.
public enum SkillEntityBridge {
    @MainActor public static func register(container: ModelContainer) {}
}

public enum SkillSpotlightIndexer {
    public static func index(_ skill: Skill) {}
    public static func remove(id: UUID) {}
    @MainActor public static func reindexAll(container: ModelContainer) {}
}

#endif
