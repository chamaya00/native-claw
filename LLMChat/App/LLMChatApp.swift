import SwiftUI
import SwiftData
import MemoryKit
import AgentKit

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
        // Background briefing for approved routines (§Phase 5). SwiftUI registers the
        // app-refresh handler; only approved routines arm a schedule, and only an authorised
        // notification is ever delivered. Best-effort (BGTaskScheduler), never a fixed alarm.
        .backgroundTask(.appRefresh(ProactivityScheduler.refreshTaskID)) {
            await ProactivityScheduler.handleRefresh(container: container)
        }
    }
}
