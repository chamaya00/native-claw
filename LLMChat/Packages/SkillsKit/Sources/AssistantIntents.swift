import Foundation
import SwiftData
import AgentKit

#if canImport(AppIntents)
import AppIntents

// MARK: - Ask Claw from anywhere (§Phase 7 system-surface invocation)
//
// Phase 6 exposed *skills* as App Intents; Phase 7 exposes the assistant *itself* so a spoken or
// typed question can be answered from Siri, the Action button, Spotlight, or the Shortcuts app —
// without opening the app. The intent runs a one-shot, read-only, on-device turn
// (`AssistantQuickResponder`): no tools, no persistence, so an out-of-app invocation can never
// perform an unapproved mutation (§B). Apps without an `AppShortcutsProvider` are invisible to the
// new Siri, so this intent is registered in `ClawShortcuts` alongside the skill runner.

/// Ask Claw a question and hear/read the answer, from any system surface.
@available(iOS 18.0, *)
public struct AskClawIntent: AppIntent {
    public static var title: LocalizedStringResource { "Ask Claw" }
    public static var description: IntentDescription {
        IntentDescription("Ask Claw a question and get an on-device answer.")
    }
    /// Answer in place (Siri speaks the dialog) rather than foregrounding the app.
    public static var openAppWhenRun: Bool { false }

    @Parameter(title: "Question", requestValueDialog: "What would you like to ask?")
    public var question: String

    public init() {}
    public init(question: String) { self.question = question }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let answer = await AssistantIntentBridge.respond(to: question)
        return .result(dialog: IntentDialog(stringLiteral: answer))
    }
}

/// App Intents are instantiated by the system, so they can't see the app's injected
/// `ModelContainer`. This bridge holds the container the app registers at launch and runs the
/// headless responder against it — the same seam `SkillEntityBridge` uses.
public enum AssistantIntentBridge {
    @MainActor private static var container: ModelContainer?

    @MainActor
    public static func register(container: ModelContainer) {
        self.container = container
    }

    @MainActor
    static func respond(to question: String) async -> String {
        guard let container else { return "Claw isn't ready yet. Open the app once, then try again." }
        return await AssistantQuickResponder.respond(to: question, container: container)
    }
}

#else

// Toolchains without AppIntents: no-op bridge so the app's launch-time registration compiles.
public enum AssistantIntentBridge {
    @MainActor public static func register(container: ModelContainer) {}
}

#endif
