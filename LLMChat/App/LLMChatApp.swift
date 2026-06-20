import SwiftUI
import SwiftData
import MemoryKit

@main
struct ClawApp: App {
    let container: ModelContainer

    init() {
        // CloudKit-mirrored memory store (§Phase 3); falls back to local-only if the
        // iCloud-container entitlement isn't present on this build.
        container = MemoryContainer.make()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
