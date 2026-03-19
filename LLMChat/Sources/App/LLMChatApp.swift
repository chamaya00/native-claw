import SwiftUI
import SwiftData

@main
struct ClawApp: App {
    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for:
                Persona.self,
                MemoryNote.self,
                TopicProfile.self,
                ImportedFile.self,
                Conversation.self,
                Message.self
            )
        } catch {
            fatalError("Failed to create SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(container)
        }
    }
}
