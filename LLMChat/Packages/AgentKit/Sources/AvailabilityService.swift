import Foundation
import Observation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Normalised availability of the on-device model. Built first (Phase 0) because
/// it wraps every AI-dependent path; the UI gates on it and degrades gracefully.
public enum AvailabilityState: Sendable, Equatable {
    case available
    case deviceNotEligible
    case appleIntelligenceNotEnabled
    case modelNotReady
    case unsupportedBuild      // FoundationModels not present in this SDK/build
    case other(String)

    /// A friendly, actionable explanation for the fallback UI.
    public var userMessage: String {
        switch self {
        case .available:
            return "Apple Intelligence is ready."
        case .deviceNotEligible:
            return "This device doesn't support Apple Intelligence. Claw needs an Apple-Intelligence-capable device."
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is turned off. Enable it in Settings → Apple Intelligence & Siri, then reopen Claw."
        case .modelNotReady:
            return "The on-device model is still downloading or preparing. This can take a few minutes after enabling Apple Intelligence — try again shortly."
        case .unsupportedBuild:
            return "This build was compiled without the Foundation Models framework. Build with Xcode 26+ on a supported SDK."
        case .other(let reason):
            return "Apple Intelligence is unavailable: \(reason)."
        }
    }
}

@Observable
@MainActor
public final class AvailabilityService {
    public private(set) var state: AvailabilityState

    public var isAvailable: Bool { state == .available }

    public init() {
        state = Self.currentState()
    }

    /// Re-read availability (e.g. on app foreground, or after the user enables AI).
    public func refresh() {
        state = Self.currentState()
    }

    private static func currentState() -> AvailabilityState {
#if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return .deviceNotEligible
            case .appleIntelligenceNotEnabled:
                return .appleIntelligenceNotEnabled
            case .modelNotReady:
                return .modelNotReady
            @unknown default:
                return .other(String(describing: reason))
            }
        @unknown default:
            return .other("unknown availability state")
        }
#else
        return .unsupportedBuild
#endif
    }
}
