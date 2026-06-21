import Foundation
import Observation

#if canImport(Speech) && canImport(AVFoundation)
import Speech
import AVFoundation
#endif

/// On-device speech-to-text for Claw (§Phase 7).
///
/// Uses the modern `SpeechAnalyzer` + `SpeechTranscriber` pipeline — **not** the deprecated
/// `SFSpeechRecognizer` (§B DO-NOT). Audio is captured with `AVAudioEngine`, converted to the
/// analyzer's preferred format, and streamed in; volatile + finalized results are surfaced as a
/// single growing `transcript` the chat input binds to. Everything runs on device, so no audio
/// leaves the phone — the privacy story stays intact.
///
/// **Locale gotcha (plan §Phase 7):** the requested locale is resolved with
/// `SpeechTranscriber.supportedLocale(equivalentTo:)`, never `Locale.current` directly, and the
/// matching language assets are downloaded proactively via `AssetInventory` so the first use is
/// instant.
///
/// The new-API surface is gated on `canImport(Speech)`; on toolchains/SDKs without it the type
/// still compiles as a no-op so the app builds everywhere.
@MainActor
@Observable
public final class VoiceTranscriber {

    public enum VoiceError: LocalizedError {
        case microphonePermissionDenied
        case localeNotSupported
        case unavailable

        public var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access is off. Enable it in Settings → Claw to use voice input."
            case .localeNotSupported:
                return "On-device speech recognition isn't available for your language yet."
            case .unavailable:
                return "Voice input needs iOS 26 with on-device speech recognition."
            }
        }
    }

    /// The growing transcript (finalized text + the current volatile tail). Bind to the input.
    public private(set) var transcript: String = ""
    /// True while the mic is live and audio is being analyzed.
    public private(set) var isListening: Bool = false
    /// True while language assets are downloading on first use.
    public private(set) var isPreparing: Bool = false
    /// Last error surfaced to the UI (permission, locale, etc.).
    public var error: String?

    public init() {}

#if canImport(Speech) && canImport(AVFoundation)
    /// Holds the live capture/analysis objects for one dictation session. Created on `start`,
    /// torn down on `stop`. Lives only on the main actor.
    private final class Engine {
        let audioEngine = AVAudioEngine()
        var analyzer: SpeechAnalyzer?
        var transcriber: SpeechTranscriber?
        var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
        var resultsTask: Task<Void, Never>?
    }

    private var engine: Engine?

    /// Whether on-device transcription is usable for the current language right now.
    public static func isSupported() async -> Bool {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) != nil
    }

    /// Start (or stop) dictation. Returns immediately; results stream into `transcript`.
    public func toggle() async {
        if isListening { await stop() } else { await start() }
    }

    public func start() async {
        guard !isListening else { return }
        error = nil
        transcript = ""

        do {
            try await requestMicrophonePermission()
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale.current) else {
                throw VoiceError.localeNotSupported
            }
            try await beginListening(locale: locale)
            isListening = true
        } catch let voiceError as VoiceError {
            error = voiceError.errorDescription
            await teardown()
        } catch {
            self.error = error.localizedDescription
            await teardown()
        }
    }

    public func stop() async {
        guard isListening else { return }
        isListening = false
        await finishAndDrain()
    }

    // MARK: - Internals

    private func requestMicrophonePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return
        case .denied:
            throw VoiceError.microphonePermissionDenied
        case .undetermined:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { throw VoiceError.microphonePermissionDenied }
        @unknown default:
            let granted = await AVAudioApplication.requestRecordPermission()
            if !granted { throw VoiceError.microphonePermissionDenied }
        }
    }

    private func beginListening(locale: Locale) async throws {
        let engine = Engine()
        self.engine = engine

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: []
        )
        engine.transcriber = transcriber
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        engine.analyzer = analyzer

        // Proactively install language assets so first use is instant (§Phase 7 / AssetInventory).
        isPreparing = true
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        isPreparing = false

        let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        // Consume results on the main actor; fold finalized text and surface the volatile tail.
        engine.resultsTask = Task { @MainActor [weak self] in
            var finalized = ""
            do {
                for try await result in transcriber.results {
                    let piece = String(result.text.characters)
                    if result.isFinal {
                        finalized += piece
                        self?.transcript = finalized
                    } else {
                        self?.transcript = finalized + piece
                    }
                }
            } catch {
                self?.error = error.localizedDescription
            }
        }

        // Configure the session for spoken capture (and playback, so TTS can duck/coexist).
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let (inputSequence, inputBuilder) = AsyncStream<AnalyzerInput>.makeStream()
        engine.inputBuilder = inputBuilder

        let inputNode = engine.audioEngine.inputNode
        let hardwareFormat = inputNode.outputFormat(forBus: 0)
        let converter = BufferConverter(targetFormat: analyzerFormat)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            guard let converted = converter.convert(buffer) else { return }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }

        engine.audioEngine.prepare()
        try engine.audioEngine.start()
        try await analyzer.start(inputSequence: inputSequence)
    }

    private func finishAndDrain() async {
        guard let engine else { return }
        self.engine = nil
        engine.audioEngine.stop()
        engine.audioEngine.inputNode.removeTap(onBus: 0)
        engine.inputBuilder?.finish()
        try? await engine.analyzer?.finalizeAndFinishThroughEndOfInput()
        engine.resultsTask?.cancel()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func teardown() async {
        isListening = false
        isPreparing = false
        await finishAndDrain()
    }

#else
    // SDKs without the Speech analyzer surface: no-op so the app and chat UI build unchanged.
    public static func isSupported() async -> Bool { false }
    public func toggle() async { error = "Voice input needs iOS 26 with on-device speech recognition." }
    public func start() async { error = "Voice input needs iOS 26 with on-device speech recognition." }
    public func stop() async {}
#endif
}

#if canImport(Speech) && canImport(AVFoundation)
/// Converts captured hardware buffers to the analyzer's preferred format off the main actor.
/// `@unchecked Sendable` because the underlying `AVAudioConverter` is single-threaded but is only
/// ever touched from the (serial) audio tap callback.
private final class BufferConverter: @unchecked Sendable {
    private let targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    init(targetFormat: AVAudioFormat?) {
        self.targetFormat = targetFormat
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let targetFormat else { return buffer }
        if buffer.format == targetFormat { return buffer }

        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: targetFormat)
        }
        guard let converter else { return nil }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var fed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, statusPtr in
            if fed {
                statusPtr.pointee = .noDataNow
                return nil
            }
            fed = true
            statusPtr.pointee = .haveData
            return buffer
        }
        return conversionError == nil ? output : nil
    }
}
#endif
