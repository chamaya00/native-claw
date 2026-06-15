import Foundation
import MemoryKit

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Context-budget discipline for the fixed on-device window. This is built in the
/// spine (Phase 1) because the ~4K window is the defining constraint of the product:
/// instructions + tools + retrieved memory + transcript + input + response headroom
/// all compete for it. Every later feature is measured against this budget.
///
/// Token measurement: Phase 1 uses a conservative chars/4 heuristic so the logic is
/// self-contained and deterministic. When the framework's exact token APIs are wired
/// in Phase 4 (alongside the Evaluations harness), swap `estimatedTokens` / `contextSize`
/// here — every call site already routes through this type.
public struct ContextBudget: Sendable {
    public let contextSize: Int
    public let summarizeThresholdRatio: Double
    public let responseHeadroom: Int

    public init(
        contextSize: Int = 4096,
        summarizeThresholdRatio: Double = 0.7,
        responseHeadroom: Int = 512
    ) {
        self.contextSize = contextSize
        self.summarizeThresholdRatio = summarizeThresholdRatio
        self.responseHeadroom = responseHeadroom
    }

    /// Conservative token estimate for a piece of text (~4 chars/token for English).
    public func estimatedTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    /// True once usage crosses the summarization threshold (default 70% of window).
    public func shouldSummarize(usedTokens: Int) -> Bool {
        Double(usedTokens) >= Double(contextSize) * summarizeThresholdRatio
    }

    /// Effective room left for the model's response.
    public func remainingForResponse(usedTokens: Int) -> Int {
        max(0, contextSize - usedTokens - responseHeadroom)
    }

    /// Distil recent turns into a compact summary used to re-seat the session.
    /// Runs as a short, separate generation so it doesn't pollute the live transcript.
    @MainActor
    public func summarize(messages: [ChatMessage]) async throws -> String {
        let transcript = messages
            .suffix(20)
            .map { "\($0.role): \($0.content)" }
            .joined(separator: "\n")

        if transcript.isEmpty { return "" }

#if canImport(FoundationModels)
        let session = LanguageModelSession(
            instructions: "Summarise the conversation below into a compact set of durable facts and open threads. Be terse — this is reused as context in a small window. No preamble."
        )
        let response = try await session.respond(
            to: transcript,
            generating: ConversationSummary.self,
            options: GenerationOptions(temperature: 0.3)
        )
        return response.content.summary
#else
        // Fallback: keep the tail verbatim, trimmed.
        return String(transcript.suffix(800))
#endif
    }
}

#if canImport(FoundationModels)
@Generable
struct ConversationSummary {
    @Guide(description: "A terse summary of durable facts and unresolved threads from the conversation")
    var summary: String
}
#endif
