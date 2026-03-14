# Vietnamese–English Vocabulary Tutor — Refined MVP Implementation Plan

## Context: What Already Exists

The app (`LLMChat/`) ships a working on-device chat powered by Apple's
Foundation Models framework. The following infrastructure is **done** and must
not be recreated:

| Asset | Status | Reuse strategy |
|-------|--------|----------------|
| `project.yml` (XcodeGen) | Done | Add new source files here as they're created |
| `LLMChatApp.swift` | Done | Replace `TabView` body with tutor entry flow |
| `Message.swift` | Done | Keep for thread bubbles; add new domain types in `AppModels.swift` |
| `LLMService.swift` | Done | Refactor — keep availability check, streaming infra, context-window recovery; add structured generation methods |
| `ChatView.swift` | Done | Gut and rebuild — keep scroll/input-bar skeleton, replace body with 3-zone layout |
| `MessageBubble.swift` | Done | Keep as-is for Zone 1 thread bubbles |
| `ChatViewModel.swift` | Done | Major rewrite — replace simple send/receive with `SessionPhase` state machine |
| `CustomizationChatView.swift` | Done | Keep for Session Lab tab (development tool, not user-facing in tutor) |
| `CustomizationViewModel.swift` | Done | Keep (independent of tutor flow) |
| `CustomizationLLMService.swift` | Done | Keep (independent of tutor flow) |
| CI/CD (4 workflows) | Done | No changes needed |
| Fastlane (5 lanes) | Done | No changes needed |
| `#if canImport(FoundationModels)` gating | Done | Follow same pattern in all new code |
| `TypingIndicatorView` | Done | Reuse in Zone 1 for tutor typing indicator |
| `UnavailableView` | Done | Reuse — update copy to Vietnamese |

**Not yet built:** Domain models, `@Generable` structs, 3-zone layout,
word grid sheet, flashcard deck, exercise overlay, topic chips, status pills,
quick-reply chips, haptics, `matchedGeometryEffect` transitions, name-capture
flow, ImagePlayground integration, learning-loop state machine.

---

## Design Principles

- Student drives what they practice; the agent drives how deep the feedback goes
- Chat-first: one screen, three zones, everything emerges from and returns to
  the thread
- Fully on-device — Foundation Models + ImagePlayground, no server, no account
- Vietnamese native speaker learning English, A1–A2 level assumed
- No persistence in MVP — all state is in-memory, lost on quit

## Out of Scope (All Phases)

Persistence, spaced repetition, audio, camera, social, notifications, iCloud,
iPad layout, settings, saved words browser, mascot/Pro tier, accessibility audit.

---

## The Learning Loop (7 Steps)

1. **Session start** — tutor greets in Vietnamese, topic chips appear in Zone 2
2. **Word generation** — Foundation Models streams 10 words into word grid sheet
3. **Word selection** — user picks 1–3 from grid, confirms
4. **Flashcard generation** — Foundation Models + ImagePlayground run concurrently
   per card
5. **Flashcard review** — swipeable full-screen sheet, unlock practice after all
   viewed
6. **Practice round** — 6 exercises (2 per word) in floating overlay card
7. **Feedback + continue** — feedback card in thread, quick reply chips to
   continue

---

## Three UI Zones

**Zone 1 — Thread** (permanent, scrollable)
Only tutor/user text bubbles, compact receipt cards, and feedback cards live
here. Activities never push into the thread — only their receipts do after
completion. **Reuse** existing `MessageBubble` for text bubbles.

**Zone 2 — Contextual Layer** (ephemeral, above input bar)
Topic chips, status pills ("✦ Đang tạo..."), quick reply chips. Spring in and
dissolve. Never affect thread scroll position. Status pill uses
`matchedGeometryEffect` to morph into the sheet handle.

**Zone 3 — Activity Overlays** (temporary, over thread)
- Word grid: `.sheet` medium detent
- Flashcard deck: `.sheet` large detent, blurred thread peek at top
- Exercise card: floating `ZStack` overlay pinned above input bar — content
  morphs in place between exercises using `.asymmetric` transition, card frame
  never moves, thread dimmed behind it

Input bar is always visible except during flashcard sheet (hidden while
full-screen).

---

## Phase 1 — Domain Models + UI Shell with Stubs

**Outcome:** Full learning loop navigable end-to-end with fake data. All
animations correct. No AI calls yet.

### 1A. New file: `LLMChat/Sources/Models/AppModels.swift`

All new value types live here. `Message.swift` stays untouched.

```
SessionPhase           — enum: greeting, topicSelection, wordGeneration,
                         wordSelection, flashcardGeneration, flashcardReview,
                         practiceRound, feedback, freeChat
LearnerProfile         — struct: name (String)
Topic                  — struct: id, emoji, labelVi, labelEn
WordEntry              — struct: id, english, vietnamese, partOfSpeech,
                         exampleSentence
Flashcard              — struct: id, wordEntry, mnemonicVi, exampleEn,
                         exampleVi, image (UIImage?)
ExerciseType           — enum: fillBlank, multipleChoice, translate
Exercise               — struct: id, type, prompt, correctAnswer, options,
                         wordEntry
ExerciseResult         — struct: exerciseId, userAnswer, isCorrect
PracticeRound          — struct: exercises [Exercise], results [ExerciseResult]
RoundFeedback          — struct: score, commentVi, corrections
QuickReply             — struct: id, labelVi, action (enum)
```

### 1B. Rewrite `ChatViewModel.swift`

Replace the current simple send/receive logic with a `SessionPhase` state
machine. **Keep** the `@MainActor @Observable` pattern already established.

Key `@Published`-equivalent properties to add:

```
phase: SessionPhase
learnerProfile: LearnerProfile?
topics: [Topic]                       — Zone 2 chips
currentWords: [WordEntry]             — word grid data
selectedWords: [WordEntry]            — user picks
flashcards: [Flashcard]               — generated cards
flashcardImages: [UUID: UIImage]      — async image results
currentExerciseIndex: Int
practiceRound: PracticeRound?
quickReplies: [QuickReply]            — Zone 2 chips
statusMessage: String?                — Zone 2 pill
isShowingWordGrid: Bool               — Zone 3 sheet
isShowingFlashcards: Bool             — Zone 3 sheet
isShowingExercise: Bool               — Zone 3 overlay
```

All learning-loop methods stubbed with `// STUB`, returning hardcoded
Vietnamese/English content after realistic `Task.sleep` delays (1–2 s).

**Do not delete** `messages`, `isGenerating`, `streamingContent` — they are
still used for Zone 1 thread bubbles.

### 1C. Rebuild `ChatView.swift`

Gut the body but **keep** the existing `ScrollViewReader` + input bar skeleton.
Replace the body with 3-zone layout:

- **Zone 1:** `ScrollView` of `MessageBubble` (already built) + new inline
  receipt/feedback card views
- **Zone 2:** `VStack` above input bar — `TopicChipBar`, `StatusPill`,
  `QuickReplyBar` (new small views, each < 50 LOC)
- **Zone 3:** `.sheet` modifiers for word grid and flashcard deck; `ZStack`
  overlay for exercise card

New sub-views to create (all in `Views/`):

| File | Purpose | Size |
|------|---------|------|
| `TopicChipBar.swift` | Horizontal scroll of topic chips | ~40 LOC |
| `StatusPill.swift` | "✦ Đang tạo..." animated pill | ~30 LOC |
| `QuickReplyBar.swift` | Quick reply chip row | ~40 LOC |
| `WordGridSheet.swift` | Selectable word grid in medium detent | ~80 LOC |
| `FlashcardSheet.swift` | Swipeable flashcard deck in large detent | ~120 LOC |
| `ExerciseOverlay.swift` | Floating exercise card with morphing content | ~120 LOC |
| `ReceiptCard.swift` | Compact inline summary for thread | ~40 LOC |
| `FeedbackCard.swift` | Score + corrections inline card | ~60 LOC |
| `NameCaptureSheet.swift` | First-launch name entry | ~50 LOC |

### 1D. Update `LLMChatApp.swift`

Replace `TabView` body:
- Show `NameCaptureSheet` on first launch (when `learnerProfile == nil`)
- Main view is the rebuilt `ChatView` (no tab bar in tutor mode)
- Keep Session Lab accessible via a hidden debug gesture or toolbar menu

### 1E. Shared utilities

Add to a new `LLMChat/Sources/Utilities/` folder:

- `Haptics.swift` — static helper with `impact()` and `notification()` methods
- `AnimationExtensions.swift` — `Animation.tutorSpring` and
  `Animation.exerciseTransition` constants

### 1F. Exercise card transition

Implement in-place content morphing for the exercise overlay:

```swift
exerciseContent(for: currentExercise)
    .id(currentExercise.id)
    .transition(.asymmetric(
        insertion: .move(edge: .trailing).combined(with: .opacity),
        removal: .move(edge: .leading).combined(with: .opacity)
    ))
    .animation(.exerciseTransition, value: currentExercise.id)
```

- Correct answer: green flash + `.success` haptic, 0.6 s delay → next
- Wrong answer: red shake + `.error` haptic, correct answer revealed, 0.8 s →
  next

### 1G. Wire `matchedGeometryEffect`

Status pill (Zone 2) morphs into the sheet drag handle when a Zone 3 sheet
presents. Use a shared `@Namespace`.

**Done-when:** All 7 steps reachable with stub data, transitions feel right,
haptics fire, exercise card morphs correctly. No AI calls.

---

## Phase 2 — Foundation Models Integration

**Outcome:** All stub AI calls replaced with real structured generation.

### 2A. Add `@Generable` structs

New file: `LLMChat/Sources/Models/GenerableModels.swift`

These are separate from `AppModels.swift` because they carry `@Generable` /
`@Guide` annotations and are tightly coupled to the model's output contract.

```swift
@Generable struct WordSet {
    @Guide(description: "10 English vocabulary words for the topic", .count(10))
    var words: [GeneratedWord]
}

@Generable struct GeneratedWord {
    @Guide(description: "English word")
    var english: String
    @Guide(description: "Vietnamese translation")
    var vietnamese: String
    @Guide(description: "Part of speech")
    var partOfSpeech: String
    @Guide(description: "Example sentence using the word")
    var exampleSentence: String
}

@Generable struct GeneratedFlashcard {
    @Guide(description: "Mnemonic hint in Vietnamese")
    var mnemonicVi: String
    @Guide(description: "Example sentence in English")
    var exampleEn: String
    @Guide(description: "Vietnamese translation of example")
    var exampleVi: String
}

@Generable struct GeneratedPracticeRound {
    @Guide(description: "6 exercises, 2 per word", .count(6))
    var exercises: [GeneratedExercise]
}

@Generable struct GeneratedExercise {
    @Guide(description: "Exercise type", .anyOf(["fillBlank", "multipleChoice", "translate"]))
    var type: String
    @Guide(description: "Exercise prompt for the student")
    var prompt: String
    @Guide(description: "The correct answer")
    var correctAnswer: String
    @Guide(description: "Multiple choice options (4 items)", .count(4))
    var options: [String]
}

@Generable struct GeneratedFeedback {
    @Guide(description: "Score out of 6", .range(0...6))
    var score: Int
    @Guide(description: "Encouraging comment in Vietnamese")
    var commentVi: String
    @Guide(description: "Corrections for wrong answers")
    var corrections: [GeneratedCorrection]
}

@Generable struct GeneratedCorrection {
    @Guide(description: "The exercise prompt")
    var prompt: String
    @Guide(description: "What the student answered")
    var studentAnswer: String
    @Guide(description: "The correct answer")
    var correctedAnswer: String
    @Guide(description: "Brief explanation in Vietnamese")
    var explanation: String
}
```

### 2B. Refactor `LLMService.swift`

**Keep:** `availabilityReason()`, `resetSession()`, `#if canImport` gating,
context-window recovery logic, actor isolation.

**Add** a dedicated tutor session (separate from the existing generic chat
session) with Vietnamese-tutor system instructions via `Instructions`. Add
five new methods:

| Method | Pattern | Notes |
|--------|---------|-------|
| `streamWords(topic:)` | `streamResponse(generating: WordSet.self)` | Stream into word grid as words arrive |
| `generateFlashcard(word:)` | `respond(generating: GeneratedFlashcard.self)` | Called concurrently via `async let` per word |
| `generateExercises(words:)` | `respond(generating: GeneratedPracticeRound.self)` | Single call for all 6 exercises |
| `generateFeedback(results:)` | `respond(generating: GeneratedFeedback.self)` | Pass actual exercise results in prompt |
| `respondFreeText(input:)` | `respond(to:)` plain string | Conversational reply; reuse existing `streamResponse` |

Build one `LanguageModelSession` per learning loop. Inject learner name, level,
and language policy in `Instructions` at session creation. Recreate session on
"Chủ đề mới".

### 2C. Replace stubs in `ChatViewModel`

Remove every `// STUB` block and wire to the real `LLMService` methods. Wrap
every call with the existing availability check pattern.

**Done-when:** AI responses are real, streaming words visible in sheet,
exercises reflect actual words, feedback references actual results.

---

## Phase 3 — ImagePlayground Integration

**Outcome:** Real illustrations on flashcards, graceful fallback.

### 3A. Add ImagePlayground to the project

Update `project.yml` to add `ImagePlayground` framework. Gate all image code
behind `#if canImport(ImagePlayground)`.

### 3B. Image generation service

Add image generation logic (can live inside `LLMService` or a small
`ImageService`). Fire one background `Task` per flashcard immediately after its
text generates.

### 3C. Update `FlashcardSheet.swift`

Observe `flashcardImages: [UUID: UIImage]` on the view model. Cross-fade from
shimmer placeholder to image as each arrives. Never block the UI.

### 3D. Fallback

If `ImageCreator` is unsupported (pre-iPhone 15 Pro) or throws, show a colored
gradient placeholder derived deterministically from the word (e.g. hash the
English word → hue). No error shown to user — silently degrade.

**Done-when:** Illustrations appear progressively on supported devices.
Unsupported devices show gradient fallback with no error state.

---

## Phase 4 — Polish & Hardening

**Outcome:** Production-ready feel, no blank or broken states.

### 4A. Streaming text in thread

Tutor bubbles type in character by character (reuse existing
`streamingContent` state from `ChatViewModel`). Show the existing
`TypingIndicatorView` briefly before first character.

### 4B. Context window management

After 10+ turns, recreate session with condensed instructions + last 3
exchanges. Build on the existing `exceededContextWindowSize` recovery in
`LLMService` — make it proactive rather than reactive.

### 4C. Error handling

All failure paths (model unavailable, timeout, cancellation, ImageCreator
failure) show friendly Vietnamese message in chat thread. Build on existing
`errorMessage` and `LLMError` patterns.

### 4D. Edge cases

- Normalize fill-in-blank answers before comparison (case, whitespace,
  diacritics)
- Confirm dialog before abandoning an in-progress exercise round
- Handle partial `WordSet` if model returns fewer than 10 words
- Gray out already-learned words when re-selecting after "Thêm từ mới"

### 4E. Animation refinement

- Chip stagger dissolve (0.05 s × index delay)
- Feedback card score badge scales in on appear
- Exercise progress bar animates width
- `matchedGeometryEffect` polish pass

**Done-when:** No crashes, no blank states, all errors visible in Vietnamese,
smooth 60 fps animations on iPhone 14 and newer.

---

## File Change Summary

| Action | File | Phase |
|--------|------|-------|
| **Create** | `Sources/Models/AppModels.swift` | 1 |
| **Create** | `Sources/Utilities/Haptics.swift` | 1 |
| **Create** | `Sources/Utilities/AnimationExtensions.swift` | 1 |
| **Create** | `Sources/Views/TopicChipBar.swift` | 1 |
| **Create** | `Sources/Views/StatusPill.swift` | 1 |
| **Create** | `Sources/Views/QuickReplyBar.swift` | 1 |
| **Create** | `Sources/Views/WordGridSheet.swift` | 1 |
| **Create** | `Sources/Views/FlashcardSheet.swift` | 1 |
| **Create** | `Sources/Views/ExerciseOverlay.swift` | 1 |
| **Create** | `Sources/Views/ReceiptCard.swift` | 1 |
| **Create** | `Sources/Views/FeedbackCard.swift` | 1 |
| **Create** | `Sources/Views/NameCaptureSheet.swift` | 1 |
| **Rewrite** | `Sources/ViewModels/ChatViewModel.swift` | 1 |
| **Rewrite** | `Sources/Views/ChatView.swift` | 1 |
| **Edit** | `Sources/App/LLMChatApp.swift` | 1 |
| **Create** | `Sources/Models/GenerableModels.swift` | 2 |
| **Edit** | `Sources/Services/LLMService.swift` | 2 |
| **Edit** | `Sources/ViewModels/ChatViewModel.swift` | 2 |
| **Edit** | `project.yml` | 3 |
| **Edit** | `Sources/Views/FlashcardSheet.swift` | 3 |
| **Edit** | various | 4 |
| **Keep** | `Sources/Models/Message.swift` | — |
| **Keep** | `Sources/Views/MessageBubble.swift` | — |
| **Keep** | `Sources/Views/CustomizationChatView.swift` | — |
| **Keep** | `Sources/ViewModels/CustomizationViewModel.swift` | — |
| **Keep** | `Sources/Services/CustomizationLLMService.swift` | — |
| **Keep** | All CI/CD workflows and Fastlane config | — |

## Shared Utilities (Created in Phase 1, Used Throughout)

```swift
// Haptics.swift
struct Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// AnimationExtensions.swift
extension Animation {
    static let tutorSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)
    static let exerciseTransition = Animation.spring(response: 0.4, dampingFraction: 0.82)
}
```
