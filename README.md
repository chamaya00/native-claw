# native-llm-app

A Vietnamese–English vocabulary tutor for iOS, powered entirely by Apple's on-device Foundation Models framework. No server, no account, no data leaves the device.

## What the app does

The app guides a learner through a structured vocabulary loop driven by an on-device language model:

1. **Greeting** — The tutor greets the learner by name in their native language and asks what topic they want to study.
2. **Topic selection** — The learner taps a topic chip (Food, Travel, Work, Home, Health, or Shopping).
3. **Word generation** — The model generates 10 vocabulary words for the chosen topic.
4. **Word selection** — The learner picks 1–3 words from a grid sheet.
5. **Flashcard generation** — The model generates a flashcard for each selected word (mnemonic, bilingual phonetics, example sentence). Illustrations are generated concurrently via ImagePlayground.
6. **Flashcard review** — The learner swipes through a full-screen flashcard deck.
7. **Practice round** — 6 exercises (multiple choice, fill-in-the-blank, translate) appear in a floating overlay card, one at a time.
8. **Feedback** — The model scores the round and provides corrections. The learner can start a new topic, add more words, retry the round, or switch to free chat.

The loop is stateful and runs entirely in memory — there is no persistence between app launches.

## Language directions

The app supports two directions, chosen at first launch:

| Direction | Native language | Target language |
|-----------|----------------|-----------------|
| `vietnameseToEnglish` | Vietnamese | English |
| `englishToVietnamese` | English | Vietnamese |

The tutor communicates with the learner in their native language and teaches the target language.

## Tech stack

| Layer | Technology |
|-------|------------|
| Language | Swift 6, async/await |
| UI | SwiftUI (`@Observable`, sheets, `matchedGeometryEffect`) |
| On-device LLM | Apple Foundation Models (`LanguageModelSession`, `@Generable`) |
| Image generation | ImagePlayground (`ImageService`) |
| Project generation | XcodeGen (YAML-based — no manual Xcode required) |
| CI/CD | GitHub Actions + Fastlane |
| Deployment target | iOS 26+ |

## Repository layout

```
native-llm-app/
├── LLMChat/
│   ├── project.yml                         # XcodeGen config
│   ├── Sources/
│   │   ├── App/
│   │   │   └── LLMChatApp.swift            # App entry point
│   │   ├── Models/
│   │   │   ├── AppModels.swift             # Domain types (Topic, WordEntry, Flashcard, Exercise, …)
│   │   │   ├── GenerableModels.swift       # @Generable structs for structured LLM output
│   │   │   └── Message.swift              # Chat message type
│   │   ├── ViewModels/
│   │   │   ├── ChatViewModel.swift         # SessionPhase state machine — drives the learning loop
│   │   │   └── CustomizationViewModel.swift# Session Lab (developer tool)
│   │   ├── Views/
│   │   │   ├── ChatView.swift              # 3-zone root view
│   │   │   ├── MessageBubble.swift         # Chat bubble (Zone 1)
│   │   │   ├── TopicChipBar.swift          # Topic chip row (Zone 2)
│   │   │   ├── StatusPill.swift            # "✦ Generating…" pill (Zone 2)
│   │   │   ├── QuickReplyBar.swift         # Post-feedback action chips (Zone 2)
│   │   │   ├── WordGridSheet.swift         # Word selection sheet (Zone 3)
│   │   │   ├── FlashcardSheet.swift        # Swipeable flashcard deck (Zone 3)
│   │   │   ├── ExerciseOverlay.swift       # Floating exercise card (Zone 3)
│   │   │   ├── FeedbackCard.swift          # Score + corrections inline card
│   │   │   ├── ReceiptCard.swift           # Compact activity receipt in thread
│   │   │   ├── NameCaptureSheet.swift      # First-launch name + direction picker
│   │   │   └── CustomizationChatView.swift # Session Lab (developer tool)
│   │   ├── Services/
│   │   │   ├── LLMService.swift            # Actor-backed on-device LLM service
│   │   │   ├── CustomizationLLMService.swift# LLM service for Session Lab
│   │   │   └── ImageService.swift          # ImagePlayground image generation
│   │   └── Utilities/
│   │       ├── Haptics.swift               # Impact and notification haptics
│   │       └── AnimationExtensions.swift   # Shared spring animation constants
│   └── Resources/
│       ├── Assets.xcassets/
│       └── Info.plist
├── .github/workflows/
│   ├── generate.yml   # Runs XcodeGen and commits the .xcodeproj
│   ├── build.yml      # Builds the app
│   ├── deploy.yml     # Uploads to TestFlight
│   └── setup-signing.yml
└── CLAUDE.md          # Coding guidelines for AI agents working on this repo
```

## UI zones

`ChatView` is divided into three permanent zones that stack vertically:

- **Zone 1 — Thread** (`ScrollView`): tutor/user message bubbles, inline feedback cards, streaming typing indicator. Never replaced — only appended to.
- **Zone 2 — Contextual layer** (above input bar): topic chips, status pills, and quick-reply chips that spring in and dissolve as the session phase changes.
- **Zone 3 — Activity overlays** (temporary, above the thread): word-grid sheet (`.medium` detent), flashcard deck (`.large` detent), and a floating exercise card (`ZStack` overlay). Each returns to the thread with a compact receipt when dismissed.

## Key source files for AI agents

| File | Role |
|------|------|
| `ChatViewModel.swift` | The central state machine. Understand `SessionPhase` and the 7-step learning loop before editing anything. |
| `LLMService.swift` | All Foundation Models calls. Uses a generic session for free chat and a separate tutor session for the structured loop. Both sessions persist across turns. |
| `GenerableModels.swift` | `@Generable` + `@Guide` structs that define the model's output contracts. Gated behind `#if canImport(FoundationModels)`. |
| `AppModels.swift` | All domain value types. Add new types here, not inline in view files. |
| `CLAUDE.md` | Coding conventions and Foundation Models framework patterns required for this project. Read before writing any new code. |

## Running locally (requires a Mac)

1. Install [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
2. From the `LLMChat/` directory: `xcodegen generate`
3. Open `LLMChat/LLMChat.xcodeproj` in Xcode 26+
4. Build and run on a physical device with Apple Intelligence enabled (iOS 26+)

The app builds on the simulator but all Foundation Models calls fall back to a word-by-word stub response. ImagePlayground is not available on the simulator.

## CI/CD

GitHub Actions runs three workflows automatically:

- **generate.yml** — triggered when `project.yml` changes; regenerates the `.xcodeproj` and commits it
- **build.yml** — triggered on every push; builds the app with Fastlane
- **deploy.yml** — triggered manually or on tag push; uploads a signed build to TestFlight

Signing secrets (`APP_STORE_CONNECT_API_KEY`, `MATCH_PASSWORD`) must be configured in the repository settings before deploy will succeed.

## Requirements

- Xcode 26 beta or later
- iOS 26 device with Apple Intelligence enabled
- Apple Developer account (for device builds and TestFlight)
