import Foundation
import SwiftData
import Observation
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// One pending A/B style choice (§Phase 5 preference picker). Two variants of an answer to
/// the user's *actual* prompt that differ on a single style axis; the user taps the one
/// they prefer and the winning style folds into the persona — explicit, on-device taste
/// signal collected without anything leaving the device.
public struct PreferenceChoice: Identifiable, Sendable {
    public let id = UUID()
    public let prompt: String
    public let dimension: StyleDimension
    public let variantA: String
    public let variantB: String
    /// The style value each variant embodies (e.g. "concise" / "thorough"), in A/B order —
    /// this is what gets stored as the winning `UserPref` value.
    public let valueA: String
    public let valueB: String
}

/// Generates occasional A/B style choices and records the winner (§Phase 5). This is the
/// low-effort, fully on-device way to collect *explicit* taste signal: two variants of the
/// real answer, differing on one axis, with a hard frequency cap so it never nags. The
/// choice is always skippable and nothing leaves the device.
@Observable
@MainActor
public final class PreferenceLearner {
    private let container: ModelContainer

    /// The choice currently offered to the user, or `nil`. Observed by the chat UI, which
    /// renders it as a card; cleared on pick or skip.
    public private(set) var pendingChoice: PreferenceChoice?

    /// Hard frequency cap: at most one offer per interval, persisted across launches so the
    /// picker stays a pleasant surprise rather than a tax on every turn.
    private static let minInterval: TimeInterval = 60 * 60 * 6   // 6 hours
    private static let lastOfferedKey = "preferenceLearner.lastOffered"

    /// Rotates the probed dimension so we don't keep asking about the same axis.
    private var dimensionCursor = 0

    public init(container: ModelContainer) {
        self.container = container
    }

    /// Decide whether to offer a style choice for the just-answered prompt, and if so build
    /// it on-device off the streaming path. Respects the frequency cap; safe to call every
    /// turn (it self-limits) and never surfaces failures — it's a best-effort nicety.
    public func maybeOffer(for prompt: String) async {
        guard pendingChoice == nil else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return }   // trivial turns aren't worth probing
        guard capReady() else { return }

#if canImport(FoundationModels)
        let dimension = StyleDimension.allCases[dimensionCursor % StyleDimension.allCases.count]
        dimensionCursor += 1
        let spec = Self.spec(for: dimension)
        do {
            // Generate both variants concurrently — independent sessions, no shared state.
            async let a = generate(prompt: trimmed, instruction: spec.instructionA, options: spec.optionsA)
            async let b = generate(prompt: trimmed, instruction: spec.instructionB, options: spec.optionsB)
            let (textA, textB) = try await (a, b)
            let cleanA = textA.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanB = textB.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanA.isEmpty, !cleanB.isEmpty, cleanA != cleanB else { return }
            pendingChoice = PreferenceChoice(
                prompt: trimmed,
                dimension: dimension,
                variantA: cleanA,
                variantB: cleanB,
                valueA: spec.valueA,
                valueB: spec.valueB
            )
            markOffered()
        } catch {
            return
        }
#endif
    }

    /// Record the user's pick: persist the `PreferencePair` and fold the winning style into
    /// an approved `UserPref`. Clears the pending choice.
    public func record(choice: PreferenceChoice, pickedA: Bool) {
        let context = ModelContext(container)
        recordPreference(
            prompt: choice.prompt,
            chosen: pickedA ? choice.variantA : choice.variantB,
            rejected: pickedA ? choice.variantB : choice.variantA,
            dimension: choice.dimension,
            chosenValue: pickedA ? choice.valueA : choice.valueB,
            context: context
        )
        pendingChoice = nil
    }

    /// Dismiss the offer without recording a preference (always skippable).
    public func skip() { pendingChoice = nil }

#if canImport(FoundationModels)
    private func generate(prompt: String, instruction: String, options: GenerationOptions) async throws -> String {
        let session = LanguageModelSession(instructions: instruction)
        return try await session.respond(to: prompt, options: options).content
    }

    /// The two generation deltas (instructions + options) and the value labels for a
    /// dimension. Length is shaped with a response-token cap; warmth with temperature.
    private static func spec(for dimension: StyleDimension) -> (
        valueA: String, valueB: String,
        instructionA: String, instructionB: String,
        optionsA: GenerationOptions, optionsB: GenerationOptions
    ) {
        switch dimension {
        case .length:
            return (
                "concise", "thorough",
                "Answer in one or two short sentences. No preamble, no lists.",
                "Answer thoroughly, with helpful detail and useful context.",
                GenerationOptions(maximumResponseTokens: 90),
                GenerationOptions(maximumResponseTokens: 400)
            )
        case .warmth:
            return (
                "matter-of-fact", "warm",
                "Answer plainly and directly in a neutral tone.",
                "Answer in a warm, friendly, encouraging tone.",
                GenerationOptions(temperature: 0.3),
                GenerationOptions(temperature: 0.9)
            )
        }
    }
#endif

    private func capReady() -> Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastOfferedKey) as? Date else {
            return true
        }
        return Date.now.timeIntervalSince(last) >= Self.minInterval
    }

    private func markOffered() {
        UserDefaults.standard.set(Date.now, forKey: Self.lastOfferedKey)
    }
}
