import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// A display-friendly snapshot of one entry in the session transcript.
struct TranscriptDisplayEntry: Identifiable, Sendable {
    let id = UUID()
    let role: String
    let content: String
}

/// User-configurable generation parameters. Always available (no SDK gating).
struct LLMGenerationConfig: Sendable {
    var useGreedySampling: Bool = false
    var temperature: Double = 1.0
}

/// Actor-backed LLM service for the customisation lab screen.
/// Maintains its own session separately from the main chat's `LLMService`.
actor CustomizationLLMService {

#if canImport(FoundationModels)
    private var session: LanguageModelSession?
    private var displayTranscript: [TranscriptDisplayEntry] = []

    // MARK: - Session Management

    func setupSession(instructions: String) {
        session = LanguageModelSession(instructions: instructions)
        displayTranscript = [
            TranscriptDisplayEntry(role: "Instructions", content: instructions)
        ]
    }

    func getTranscript() -> [TranscriptDisplayEntry] {
        displayTranscript
    }

    func isAvailable() -> Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    func availabilityReason() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device is not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled. Enable it in Settings > Apple Intelligence & Siri."
            case .modelNotReady:
                return "The on-device AI model is not ready yet. It may still be downloading."
            @unknown default:
                return "The on-device language model is unavailable."
            }
        }
    }

    // MARK: - Response Streaming

    func streamResponse(
        prompt: String,
        instructions: String,
        config: LLMGenerationConfig,
        onPartial: @Sendable @escaping (String) -> Void
    ) async throws -> [TranscriptDisplayEntry] {
        guard isAvailable() else { throw LLMError.unsupportedDevice }

        // Lazily create session on first send using current instructions.
        if session == nil {
            setupSession(instructions: instructions)
        }
        let s = session!

        let options: GenerationOptions = config.useGreedySampling
            ? GenerationOptions(sampling: .greedy)
            : GenerationOptions(temperature: config.temperature)

        displayTranscript.append(TranscriptDisplayEntry(role: "User", content: prompt))

        var finalContent = ""
        do {
            let stream = s.streamResponse(to: prompt, options: options)
            for try await partial in stream {
                finalContent = partial.content
                onPartial(partial.content)
            }
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize {
            // Condense transcript: keep instructions entry + last exchange.
            let entries = Array(s.transcript)
            var condensed: [Transcript.Entry] = []
            if let first = entries.first { condensed.append(first) }
            if entries.count > 1, let last = entries.last { condensed.append(last) }
            session = LanguageModelSession(transcript: Transcript(entries: condensed))
            // Mirror the condensation in display transcript.
            let keep = min(2, displayTranscript.count)
            displayTranscript = Array(displayTranscript.suffix(keep))
            throw LLMError.contextWindowExceeded
        } catch {
            throw LLMError.generationFailed(error.localizedDescription)
        }

        displayTranscript.append(TranscriptDisplayEntry(role: "Assistant", content: finalContent))
        return displayTranscript
    }

#else
    // MARK: - Simulator stubs

    private var displayTranscript: [TranscriptDisplayEntry] = []

    func setupSession(instructions: String) {
        displayTranscript = [
            TranscriptDisplayEntry(role: "Instructions", content: instructions)
        ]
    }

    func getTranscript() -> [TranscriptDisplayEntry] { displayTranscript }

    func isAvailable() -> Bool { false }

    func availabilityReason() -> String? {
        "Foundation Models is not available in the current SDK. A physical device running iOS 26 with Apple Intelligence is required."
    }

    func streamResponse(
        prompt: String,
        instructions: String,
        config: LLMGenerationConfig,
        onPartial: @Sendable @escaping (String) -> Void
    ) async throws -> [TranscriptDisplayEntry] {
        if displayTranscript.isEmpty {
            displayTranscript = [TranscriptDisplayEntry(role: "Instructions", content: instructions)]
        }
        displayTranscript.append(TranscriptDisplayEntry(role: "User", content: prompt))

        let words = "This is a simulated streaming response. The Apple Foundation Models framework requires a physical device running iOS 26 with Apple Intelligence capabilities.".split(separator: " ")
        var accumulated = ""
        for word in words {
            try await Task.sleep(nanoseconds: 80_000_000)
            accumulated += (accumulated.isEmpty ? "" : " ") + word
            onPartial(accumulated)
        }

        displayTranscript.append(TranscriptDisplayEntry(role: "Assistant", content: accumulated))
        return displayTranscript
    }
#endif
}
