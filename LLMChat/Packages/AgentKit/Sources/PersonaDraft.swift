import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Structured output of the onboarding conversation. Produced via guided generation
/// so we never parse free-form text into a persona.
@Generable
public struct PersonaDraft {
    @Guide(description: "The name the user chose for the assistant")
    public var name: String

    @Guide(description: "The desired vibe and communication style, e.g. 'chill and direct' or 'warm and encouraging'")
    public var vibe: String

    @Guide(description: "Core values that should guide responses, e.g. 'concise', 'honest', 'synthesis-focused'", .maximumCount(5))
    public var values: [String]

    @Guide(description: "Topics the user cares about most right now, if mentioned; empty if not", .maximumCount(8))
    public var expertiseAreas: [String]
}

#else

/// Fallback shape so the app's onboarding flow compiles on SDKs without FoundationModels.
public struct PersonaDraft {
    public var name: String
    public var vibe: String
    public var values: [String]
    public var expertiseAreas: [String]

    public init(name: String, vibe: String, values: [String], expertiseAreas: [String]) {
        self.name = name
        self.vibe = vibe
        self.values = values
        self.expertiseAreas = expertiseAreas
    }
}

#endif
