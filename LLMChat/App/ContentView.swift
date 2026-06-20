import SwiftUI
import SwiftData
import MemoryKit
import AgentKit
import SkillsKit

/// Root view. Gates on (1) model availability, then (2) whether a Persona exists:
/// - unavailable      → AvailabilityUnavailableView (Phase 0 graceful fallback)
/// - available, none  → OnboardingView
/// - available, set   → ChatView
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var personas: [Persona]

    // The engine lives here so it survives view transitions within a session.
    @State private var engine: ConversationEngine?

    var body: some View {
        Group {
            if let engine {
                if !engine.isAvailable {
                    AvailabilityUnavailableView(state: engine.availability.state)
                        .transition(.opacity)
                } else if personas.isEmpty {
                    OnboardingView(engine: engine, container: modelContext.container) { }
                        .transition(.opacity)
                } else {
                    ChatView(engine: engine, container: modelContext.container)
                        .transition(.opacity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: personas.isEmpty)
        .task {
            if engine == nil {
                engine = ConversationEngine(container: modelContext.container)
            }
            // Make approved skills resolvable by the system (Siri/Spotlight/Shortcuts) and
            // reconcile their Spotlight index once per launch — picks up skills mirrored in
            // from another device since last run (§Phase 6, mirrors the memory bridge).
            SkillEntityBridge.register(container: modelContext.container)
            SkillSpotlightIndexer.reindexAll(container: modelContext.container)
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                engine?.availability.refresh()
            case .background:
                engine?.invalidate()
                // Re-arm the briefing schedule on the way out if any routine is approved
                // (§Phase 5). Idempotent; no-op when there's nothing to schedule.
                ProactivityScheduler.scheduleIfNeeded(container: modelContext.container)
            default:
                break
            }
        }
    }
}
