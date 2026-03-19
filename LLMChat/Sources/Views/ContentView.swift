import SwiftUI
import SwiftData

/// Root view — gates on whether a Persona exists.
/// If no Persona: show OnboardingView.
/// If Persona exists: show ChatView.
struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var personas: [Persona]

    // Shared AgentService lives here so it survives view transitions
    @State private var agentService: AgentService?

    var body: some View {
        Group {
            if let service = agentService {
                if personas.isEmpty {
                    OnboardingView(
                        agentService: service,
                        container: modelContext.container,
                        onComplete: { /* @Query personas will refresh */ }
                    )
                    .transition(.opacity)
                } else {
                    ChatView(agentService: service, container: modelContext.container)
                        .transition(.opacity)
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: personas.isEmpty)
        .task {
            if agentService == nil {
                agentService = AgentService(container: modelContext.container)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                agentService?.invalidateSession()
            }
        }
    }
}
