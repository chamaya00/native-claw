import Foundation
import Observation

@MainActor
@Observable
final class CustomizationViewModel {

    // MARK: - Session configuration (bound to UI controls)

    var instructions: String = "You are a helpful assistant."
    var useGreedySampling: Bool = false
    var temperature: Double = 1.0

    // MARK: - Chat state

    private(set) var messages: [Message] = []
    private(set) var streamingContent: String = ""
    private(set) var isGenerating: Bool = false
    private(set) var errorMessage: String?

    // MARK: - Transcript state

    private(set) var transcriptEntries: [TranscriptDisplayEntry] = []

    // MARK: - Model availability

    private(set) var isModelUnavailable: Bool = false
    private(set) var unavailabilityReason: String?

    // MARK: - Private

    private let service = CustomizationLLMService()

    // MARK: - Init

    init() {
        Task {
            let reason = await service.availabilityReason()
            isModelUnavailable = (reason != nil)
            unavailabilityReason = reason
        }
    }

    // MARK: - Session control

    /// Recreates the session with current settings, clearing all chat and transcript history.
    func applySettings() {
        messages = []
        streamingContent = ""
        errorMessage = nil
        transcriptEntries = []
        Task {
            await service.setupSession(instructions: instructions)
            transcriptEntries = await service.getTranscript()
        }
    }

    // MARK: - Messaging

    func sendMessage(_ text: String) async {
        guard !text.isEmpty, !isGenerating else { return }

        messages.append(Message(role: .user, content: text))
        isGenerating = true
        errorMessage = nil
        streamingContent = ""

        let config = LLMGenerationConfig(
            useGreedySampling: useGreedySampling,
            temperature: temperature
        )
        let currentInstructions = instructions

        do {
            let updatedTranscript = try await service.streamResponse(
                prompt: text,
                instructions: currentInstructions,
                config: config
            ) { [weak self] partial in
                Task { @MainActor [weak self] in
                    self?.streamingContent = partial
                }
            }
            messages.append(Message(role: .assistant, content: streamingContent))
            transcriptEntries = updatedTranscript
        } catch LLMError.contextWindowExceeded {
            errorMessage = LLMError.contextWindowExceeded.errorDescription
            transcriptEntries = await service.getTranscript()
        } catch {
            errorMessage = error.localizedDescription
            messages.append(Message(
                role: .assistant,
                content: "Sorry, I encountered an error. Please try again."
            ))
        }

        streamingContent = ""
        isGenerating = false
    }
}
