# Vietnamese ↔ English Direction Selector — Feasibility & Implementation Plan

## Executive Summary

**Feasibility: High.** The app's architecture already stores bilingual data (Vietnamese + English) in every `WordEntry`, `Flashcard`, and `Topic`. Vietnamese is a supported language in Apple's Foundation Models framework (added in iOS 26.1). The main work is parameterizing the currently hardcoded language direction across ~7 files rather than building new infrastructure.

---

## Current State

| Aspect | Current Implementation |
|--------|----------------------|
| **UI language** | Hardcoded Vietnamese (all labels, buttons, status messages) |
| **Learning direction** | Vietnamese speaker → learns English |
| **LLM instructions** | Vietnamese system prompt, asks model to teach English |
| **TTS** | Hardcoded `en-US` only |
| **Data models** | Already bilingual: `WordEntry` has `english` + `vietnamese`, `Topic` has `labelVi` + `labelEn`, `Flashcard` has `phoneticVi` + `phoneticEn` |
| **Exercises** | Prompts in Vietnamese, answers in English |
| **Foundation Models language support** | Vietnamese supported since iOS 26.1 |

---

## Critical Feasibility Factor: Apple Foundation Models

Vietnamese was added to Apple's `supportedLanguages` in iOS 26.1 (alongside Danish, Dutch, Norwegian, etc.), bringing the total to 16 languages. This means:
- The on-device model **can** generate Vietnamese text natively
- The `SystemLanguageModel.default.supportedLanguages` check will pass for Vietnamese
- No server-side fallback is needed

**Risk:** Users on iOS 26.0 (not 26.1+) won't have Vietnamese support in Foundation Models. The app should check `supportedLanguages` and gracefully degrade.

---

## What the Selector Enables

| Mode | UI Language | Learner speaks | Learns | Use Case |
|------|-------------|----------------|--------|----------|
| **Vi → En** (current) | Vietnamese | Vietnamese | English | Vietnamese native learning English |
| **En → Vi** (new) | English | English | Vietnamese | English speaker learning Vietnamese |

---

## Implementation Plan

### Step 1: Add `LanguageDirection` Model

**File:** `AppModels.swift`

Add an enum that captures the two directions:

```swift
enum LanguageDirection: String, CaseIterable {
    case vietnameseToEnglish  // Vietnamese speaker learning English (current behavior)
    case englishToVietnamese  // English speaker learning Vietnamese

    var nativeLanguage: String { ... }    // "vi" or "en"
    var targetLanguage: String { ... }    // "en" or "vi"
    var nativeLabel: String { ... }       // Display label in native language
    var ttsLanguageCode: String { ... }   // For AVSpeechSynthesisVoice
}
```

**Effort:** Small — one new enum with computed properties.

---

### Step 2: Add Direction to `LearnerProfile` + Persistence

**Files:** `AppModels.swift`, `ChatViewModel.swift`

- Add `direction: LanguageDirection` to `LearnerProfile`
- Persist via `@AppStorage` or `UserDefaults` so it survives app restarts
- Surface the selector in `NameCaptureSheet` (during onboarding) and optionally in a settings menu

**Effort:** Small.

---

### Step 3: Direction Selector UI

**File:** `NameCaptureSheet.swift` (primary), possibly a new settings access point

Add a `Picker` or segmented control to the onboarding sheet:

```
┌─────────────────────────────────┐
│  What's your name?              │
│  [_______________]              │
│                                 │
│  I want to learn:               │
│  [🇻🇳→🇬🇧 English] [🇬🇧→🇻🇳 Tiếng Việt] │
│                                 │
│  [Bắt đầu học! / Start!]       │
└─────────────────────────────────┘
```

Also allow switching direction from the chat view (e.g., toolbar menu item) which resets the tutor session.

**Effort:** Small-medium.

---

### Step 4: Parameterize LLM Instructions

**File:** `LLMService.swift`

The tutor session instructions are currently a hardcoded Vietnamese string. Parameterize them:

- **Vi→En direction:** Keep current Vietnamese instructions (teach English to Vietnamese speaker)
- **En→Vi direction:** English instructions (teach Vietnamese to English speaker)

The `getOrCreateTutorSession` method gains a `direction` parameter. All downstream methods (`streamGreeting`, `streamWords`, `generateFlashcard`, `generateExercises`, `generateFeedback`) pass the direction through to shape their prompts.

**Key prompts to parameterize (~6 places):**
1. Tutor session system instructions (line 48-53)
2. Greeting prompt (line 155)
3. Word generation prompt (line 190)
4. Flashcard generation prompt (line 218)
5. Exercise generation prompt (line 248)
6. Feedback generation prompt (line 290)

**Effort:** Medium — each prompt needs a direction-aware variant, but they're all string templates.

---

### Step 5: Parameterize UI Strings

**Files:** `ChatView.swift`, `TopicChipBar.swift`, `QuickReplyBar.swift`, `StatusPill.swift`, `WordGridSheet.swift`, `ExerciseOverlay.swift`, `FeedbackCard.swift`, `FlashcardSheet.swift`

All hardcoded Vietnamese UI strings need direction-aware variants. Two approaches:

**Option A — Inline ternary (simpler, recommended for MVP):**
```swift
Text(direction == .vietnameseToEnglish ? "Nhắn tin..." : "Message...")
```

**Option B — String catalog / .lproj localization (more scalable):**
Full Apple localization with `String(localized:)`. Better long-term but heavier upfront.

**Recommendation:** Option A for MVP. The app has ~30-40 user-facing strings. A ternary or computed property per string is manageable and keeps the change self-contained.

**Effort:** Medium — many touchpoints but each is straightforward.

---

### Step 6: Parameterize TTS Voice

**File:** `FlashcardSheet.swift`

Change from hardcoded `en-US` to direction-aware:

```swift
// For the target language word pronunciation
utterance.voice = AVSpeechSynthesisVoice(language: direction.ttsLanguageCode)
```

For En→Vi mode, the TTS should pronounce Vietnamese words using `vi-VN`.

**Effort:** Small — one line change + pass direction through.

---

### Step 7: Flip Data Model Accessors

**Files:** `AppModels.swift`, throughout views

The `WordEntry`, `Flashcard`, and `Topic` models already have both languages. Add computed properties that respect direction:

```swift
extension WordEntry {
    func nativeWord(for direction: LanguageDirection) -> String {
        direction == .vietnameseToEnglish ? vietnamese : english
    }
    func targetWord(for direction: LanguageDirection) -> String {
        direction == .vietnameseToEnglish ? english : vietnamese
    }
}
```

Similarly for `Topic` (show `labelVi` or `labelEn` as primary) and `Flashcard` (which phonetic to show first).

**Effort:** Small-medium.

---

### Step 8: Adapt Exercises for Reverse Direction

**Files:** `AppModels.swift` (stub exercises), `ExerciseOverlay.swift`

In En→Vi mode:
- Multiple choice: "What does 'phở' mean?" → answer in English
- Translation: "Translate to Vietnamese: 'kitchen'" → answer: "nhà bếp"
- Fill-in-blank: Vietnamese sentence with blank

The LLM-generated exercises (Step 4) will handle this via prompt parameterization. The stub exercises need manual flipping.

**Effort:** Medium.

---

### Step 9: Foundation Models Language Check

**File:** `LLMService.swift`

Add a `supportedLanguages` check for the selected direction:

```swift
guard SystemLanguageModel.default.supportedLanguages.contains(
    Locale.Language(identifier: direction.targetLanguage)
) else {
    // Show unsupported message, suggest the other direction
}
```

This gracefully handles iOS 26.0 users (where Vietnamese may not be in `supportedLanguages` yet).

**Effort:** Small.

---

## Risk Assessment

| Risk | Severity | Mitigation |
|------|----------|------------|
| Vietnamese not in `supportedLanguages` on older iOS 26.0 | Medium | Runtime check + fallback to Vi→En only |
| LLM quality for Vietnamese generation may be lower than English | Low-Medium | Test with real device; Vietnamese is officially supported |
| Stub phonetics only cover Vietnamese→English phonemes | Low | Add English phonetic approximations for Vietnamese words in stubs |
| UI string count grows (2x strings) | Low | Manageable at ~30-40 strings; consider .lproj later |
| Context window pressure from bilingual prompts | Low | Prompts don't grow significantly; still single-direction per session |

---

## Estimated Scope

| Step | Files Touched | Complexity |
|------|--------------|------------|
| 1. `LanguageDirection` enum | 1 | Small |
| 2. Profile + persistence | 2 | Small |
| 3. Selector UI | 1-2 | Small-Medium |
| 4. LLM prompt parameterization | 1 | Medium |
| 5. UI string parameterization | ~8 | Medium |
| 6. TTS voice | 1 | Small |
| 7. Data model accessors | 1-2 | Small-Medium |
| 8. Exercise adaptation | 2 | Medium |
| 9. Language availability check | 1 | Small |
| **Total** | **~12 files** | **Medium overall** |

---

## Recommendation

This is a **well-scoped, medium-effort feature** that leverages existing bilingual data structures. The biggest piece of work is parameterizing the ~6 LLM prompts and ~30-40 UI strings — tedious but not complex.

**Suggested approach:**
1. Start with Steps 1-3 (model + UI selector) to get the direction wired through
2. Then Step 4 (LLM prompts) — this is the highest-value change
3. Steps 5-8 in parallel — UI strings, TTS, data accessors, exercises
4. Step 9 last — availability guard

The app can ship the selector incrementally: even with just Steps 1-4 done, the core learning loop works in both directions.
