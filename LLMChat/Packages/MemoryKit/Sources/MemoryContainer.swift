import Foundation
import SwiftData
import os

/// Builds the app's single `ModelContainer` (§Phase 3).
///
/// The differentiator is durable, user-owned memory that *follows the person across
/// their devices* — so the store is mirrored to the user's **private** CloudKit
/// database (no server of ours, no data leaving the user's iCloud). Every model the
/// app persists is registered here so the whole schema mirrors as one unit.
///
/// Resilience: enabling CloudKit requires the iCloud-container entitlement at runtime.
/// On a build that isn't signed with that capability (the simulator, an un-provisioned
/// profile), creating the cloud-backed container throws — so we fall back to a
/// local-only store rather than `fatalError`-ing. The app stays fully functional;
/// only cross-device sync is unavailable until the container is provisioned.
public enum MemoryContainer {

    private static let log = Logger(subsystem: "com.charlesamaya.llmchat", category: "MemoryContainer")

    /// Every persisted `@Model`. One list, so the container and any in-memory test
    /// store stay in lockstep.
    public static var schema: Schema {
        Schema([
            Persona.self,
            MemoryNote.self,
            ImportedFile.self,
            Conversation.self,
            Message.self,
            UserPref.self,
            PreferencePair.self,
            SuggestedRoutine.self,
            Skill.self,
            StreamlineGrant.self,
            RoutingPolicy.self
        ])
    }

    /// `true` when the live container is mirroring to CloudKit (false after fallback).
    /// Written once during `make()` at launch and read on the main thread thereafter;
    /// `nonisolated(unsafe)` documents that single-assignment contract to Swift 6.
    nonisolated(unsafe) public private(set) static var isCloudSyncing = false

    /// Create the shared container: CloudKit-private if the entitlement is present,
    /// otherwise a local-only store.
    public static func make() -> ModelContainer {
        let schema = schema
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .automatic
            )
            let container = try ModelContainer(for: schema, configurations: config)
            isCloudSyncing = true
            log.info("Memory store initialised with CloudKit private-database mirroring.")
            return container
        } catch {
            log.warning("CloudKit mirroring unavailable (\(error.localizedDescription, privacy: .public)); falling back to local-only store.")
            return makeLocal(schema: schema)
        }
    }

    private static func makeLocal(schema: Schema) -> ModelContainer {
        do {
            let config = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            isCloudSyncing = false
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create local SwiftData ModelContainer: \(error)")
        }
    }
}
