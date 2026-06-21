import Foundation
import Observation

#if canImport(AVFoundation)
import AVFoundation
#endif

/// On-device text-to-speech for Claw's voice mode (§Phase 7).
///
/// Wraps `AVSpeechSynthesizer` — the native, offline TTS path. When voice mode is on the chat
/// speaks the assistant's final reply aloud; nothing is sent off device. Kept deliberately small:
/// speak, stop, and an `isSpeaking` flag the UI can reflect.
@MainActor
@Observable
public final class SpeechSpeaker {

#if canImport(AVFoundation)
    private let synthesizer = AVSpeechSynthesizer()
    public var isSpeaking: Bool { synthesizer.isSpeaking }
#else
    public var isSpeaking: Bool { false }
#endif

    public init() {}

    /// Speak `text` aloud, replacing anything currently being spoken.
    public func speak(_ text: String) {
#if canImport(AVFoundation)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        // Coexist with capture: speak through the shared session without tearing down recording.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        synthesizer.speak(utterance)
#endif
    }

    public func stop() {
#if canImport(AVFoundation)
        synthesizer.stopSpeaking(at: .immediate)
#endif
    }
}
