# Claude Guidelines – native-llm-app

## Apple Foundation Models: Implementation Guidelines

For all Apple Foundation Models work in this project, follow framework-native
patterns from the official developer documentation and WWDC 2025 sessions:

- **WWDC 2025 Session 286** – Meet the Foundation Models framework
  https://developer.apple.com/videos/play/wwdc2025/286
- **WWDC 2025 Session 301** – Deep Dive: Foundation Models framework
  https://developer.apple.com/videos/play/wwdc2025/301/
- **Framework reference**
  https://developer.apple.com/documentation/FoundationModels#overview

---

### Sessions & State Management

Use `LanguageModelSession` as the primary entry point. It is stateful and
manages the conversation transcript automatically—do not manually concatenate
history strings into a single prompt.

```swift
// Correct: let the session manage transcript/context
let session = LanguageModelSession(instructions: "You are a helpful assistant.")
let response = try await session.respond(to: userInput)

// Wrong: building a manual context string then creating a new session each turn
let session = LanguageModelSession()
let response = try await session.respond(to: "\(history)\nUser: \(prompt)\nAssistant:")
```

Create the session once and reuse it across turns within a conversation.
Only recreate when starting a new conversation or recovering from a context
overflow (see Error Handling below).

---

### Availability Check

Always check availability before creating a session. Gate the UI on the result.

```swift
let model = SystemLanguageModel.default

switch model.availability {
case .available:
    // Proceed
case .unavailable(let reason):
    // Show fallback UI with reason
}
```

Check `supportedLanguages` when the app accepts multi-language input:

```swift
guard model.supportedLanguages.contains(Locale.current.language) else {
    // Show unsupported-language message
    return
}
```

---

### Structured Output – `@Generable` and `@Guide`

Prefer `@Generable` for any structured output. Do **not** ask the model to
return JSON/CSV and parse it manually—constrained decoding is faster, safer,
and type-safe.

```swift
@Generable
struct SearchSuggestions {
    @Guide(description: "Suggested search terms", .count(4))
    var terms: [String]
}

let response = try await session.respond(
    to: prompt,
    generating: SearchSuggestions.self
)
let terms = response.content.terms
```

Use `@Guide` to constrain values at compile time:

| Type | Example |
|------|---------|
| `Int` | `@Guide(.range(1...10))` |
| `Array` | `@Guide(.count(3))` or `@Guide(.maximumCount(5))` |
| `String` | `@Guide(description: "A full name")` |
| `String` | `@Guide(.anyOf(["yes", "no"]))` |
| `String` | `@Guide(Regex { … })` |

Property **declaration order** influences generation quality and animation
smoothness in streaming — place higher-priority fields first.

---

### Streaming

Use `streamResponse` to keep the UI responsive during generation. Bind partial
results directly to SwiftUI state.

```swift
@Generable struct Itinerary {
    var title: String
    var days: [Day]
}

@State private var itinerary: Itinerary.PartiallyGenerated?

let stream = session.streamResponse(to: prompt, generating: Itinerary.self)
for try await partial in stream {
    itinerary = partial   // SwiftUI updates automatically
}
```

Gate interactive controls with `session.isResponding`:

```swift
Button("Send") { … }
    .disabled(session.isResponding)
```

---

### Tool Calling

Conform to the `Tool` protocol when the model needs to call external code.
Attach tools at session initialisation only.

```swift
struct GetWeatherTool: Tool {
    let name = "getWeather"
    let description = "Retrieve weather for a city"   // keep brief (~1 sentence)

    @Generable
    struct Arguments {
        @Guide(description: "The city name")
        var city: String
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        // … fetch data …
        return ToolOutput("Temperature is 22 °C")
    }
}

let session = LanguageModelSession(
    tools: [GetWeatherTool()],
    instructions: "Help users with weather."
)
```

Tool-naming rules: short readable English (`findContact`, `getWeather`), no
abbreviations. Descriptions must be minimal—every token adds latency.

---

### Error Handling and Context Recovery

Handle `LanguageModelSession.GenerationError.exceededContextWindowSize` by
creating a new session with a condensed transcript rather than propagating the
error raw.

```swift
do {
    let response = try await session.respond(to: prompt)
} catch LanguageModelSession.GenerationError.exceededContextWindowSize {
    // Preserve system instructions + last exchange only
    var condensed = [Transcript.Entry]()
    if let first = allEntries.first { condensed.append(first) }
    if allEntries.count > 1, let last = allEntries.last { condensed.append(last) }
    session = LanguageModelSession(transcript: Transcript(entries: condensed))
}
```

Do **not** match against the error's `localizedDescription` string—use the
typed error case.

---

### Generation Options

```swift
// Deterministic (same output for same input)
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(sampling: .greedy)
)

// Reduced variance
let response = try await session.respond(
    to: prompt,
    options: GenerationOptions(temperature: 0.5)
)
```

---

### Specialised Use Cases

Use `SystemLanguageModel(useCase:)` when the task fits a built-in adapter;
this improves latency and accuracy.

```swift
// Content tagging
let session = LanguageModelSession(
    model: SystemLanguageModel(useCase: .contentTagging)
)
```

---

### Dynamic Schemas (Runtime-Defined Structures)

When the output shape is not known at compile time, use `DynamicGenerationSchema`:

```swift
let property = DynamicGenerationSchema.Property(
    name: "question",
    schema: DynamicGenerationSchema(type: String.self)
)
let schema = try GenerationSchema(root: root, dependencies: [dep])
let response = try await session.respond(to: prompt, schema: schema)
let value = try response.content.value(String.self, forProperty: "question")
```

Prefer `@Generable` when the shape is known at compile time.

---

### Device Scope and Privacy

- All inference runs on-device; no data leaves the device.
- The model is optimised for: **summarisation, extraction, classification**.
- It is **not** designed for advanced reasoning or world-knowledge queries—break
  complex tasks into smaller, focused prompts.
- Tools that access system APIs (Contacts, Calendar, etc.) trigger native
  permission prompts automatically.

---

### Developer Tooling

- Use Xcode Playgrounds with `import Playgrounds` + `#Playground { … }` for
  rapid prompt iteration.
- Profile request latency with Instruments before assuming a prompt is "fast
  enough."
- Gate all FoundationModels code behind `#if canImport(FoundationModels)` so
  the project builds on simulators and older SDKs without a stub divergence.
