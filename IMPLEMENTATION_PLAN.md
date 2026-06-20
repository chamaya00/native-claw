# IMPLEMENTATION_PLAN.md — “Otto” (working title)

**A fully iOS-native, privacy-first personal executive assistant that personalizes over time.**
Companion to `PRD_consumer_assistant.md` (v0.3). This document is written for **Claude Code** to execute phase by phase.

- **Platform:** iOS 26+ / iPadOS 26+ (Apple-Intelligence-capable devices).
- **Language/tooling:** Swift 6 (strict concurrency), SwiftUI, SwiftData, Xcode 27.
- **Frameworks:** FoundationModels, App Intents, Speech (SpeechAnalyzer), CloudKit, BackgroundTasks, NaturalLanguage, Vision (via built-in FM tools), AVFoundation.
- **Build constraint:** developer has **no Mac** — all builds run on GitHub Actions macOS runners and ship to TestFlight (see §C).

-----

## Status (live)

- **Phase 0 — built.** Modular skeleton (§D), `AvailabilityService` with a normalised
  state + graceful fallback UI, on-device round-trip via the conversation core, CI to
  TestFlight preserved (Xcode-26 selection, XcodeGen, Fastlane).
- **Phase 1 — built.** `ConversationEngine` (streaming partial-snapshot turns, tool
  dispatch, SwiftData persistence), `PersonaStore`, `ContextBudget` (usage estimate →
  ~70% summarisation → typed re-seat on `.exceededContextWindowSize`), central
  `ApprovalGate`, and the first mutating *system* tool `createReminder` (EventKit,
  approval-gated). The pre-existing Claw memory tools, onboarding, and chat/memory UI
  were carried over into the new modules; `AgentService`, dead `Haptics`/animation
  helpers, and the unused `ImagePlayground` dependency were deprecated and removed.
- **Phase 2 — built.** Tool library expanded in `ToolsKit`: read-only `readCalendar`
  (EventKit), `lookupContact` (Contacts), `fetchWebPage` (URLSession + HTML→text
  pre-digest), `lookupPlace` (MapKit `MKLocalSearch`); and the approval-gated
  `createCalendarEvent` (EventKit write through `ApprovalGate`, new `CalendarEventDraft`
  + confirmation card). **Multimodal capture:** `MemoryKit.ImageProcessor` runs
  Vision OCR + barcode detection on-device, folding a *compact text digest* (not raw
  pixels) into the next turn to protect the 4K budget; images attach via `PhotosPicker`,
  and PDFs now extract text via PDFKit. **Dynamic tool selection:** `ToolSelector` picks
  only the tools plausibly relevant to a turn (memory tools always-on); the engine grows
  its attached set lazily and re-seats the session when it changes. **Tool-call cards:**
  the engine records which tools ran per turn and surfaces them as chips under the
  assistant bubble. New `Info.plist` usage strings for Calendars + Contacts.
- **Phase 3 — built.** The memory loop. `MemoryContainer` mirrors the whole schema to
  the user's **private CloudKit database** (`cloudKitDatabase: .automatic`), with a
  runtime fallback to a local-only store when the iCloud entitlement isn't present so
  unsigned/CI builds never crash. The Phase-3 memory types ship now — `UserPref`,
  `PreferencePair`, `SuggestedRoutine`, `Skill`, `StreamlineGrant` — each modelled to the
  CloudKit rules (no `.unique`, all properties defaulted, relationships optional). A
  `MemoryManager` curation pass distils durable facts from recent turns into the review
  inbox as **unapproved** notes (never injected, never indexed) and flags sensitive ones;
  the engine runs it off the streaming path every few turns. Retrieval is contributed to
  the system via App Intents entity schemas: `MemoryFactEntity` (`IndexedEntity`) +
  `MemoryFactQuery`, donated to the Spotlight index (`MemorySpotlightIndexer`) on approve/
  edit/delete and reconciled once per launch. The **"what you know about me"** browser now
  reviews/approves curated candidates, edits facts in place, deletes, exports, and
  **"forget everything"** wipes the store and the index. CloudKit entitlements +
  `remote-notification` background mode added.

**Deviations from the letter of this plan (intentional):**

1. **Modules are XcodeGen framework targets, not separate `Package.swift` packages.**
   This gives the same §D module isolation and enforced `import` boundaries while
   keeping one CI-driven spec and one deployment target — avoiding per-package
   platform/tools-version wiring that can't be verified without a Mac. Re-splitting
   into SPM packages later is mechanical.
2. **App target/scheme stay named `LLMChat`** (product name "Claw") so the existing
   build/deploy/generate workflows and Fastlane lanes keep working unchanged.
3. **`ContextBudget` uses a deterministic chars/4 token estimate** in Phase 1. The
   call site is the single seam to swap in the framework's exact token APIs alongside
   the Evaluations harness in Phase 4.
4. **`ModelRouter` is deferred to Phase 4** (where it earns its keep) rather than
   shipped as a Phase-1 stub.
5. **Phase 2 image input is OCR-to-text, not raw image input.** The plan's primary
   guidance is to pre-digest images (OCR/barcode) to conserve the 4K window; we do
   exactly that via Vision in `ImageProcessor`. Raw image input for genuine visual
   reasoning is left as a documented seam rather than shipped now, since that WWDC26
   API surface can't be verified without a device.
6. **Dynamic tool selection grows the attached set lazily** instead of recomputing a
   fresh per-turn tool list. CLAUDE.md mandates attaching tools at session init, so the
   engine starts with the always-on memory tools and only re-seats the session when a
   turn needs a tool it hasn't attached — buying back budget without per-turn churn or
   losing transcript continuity. The keyword heuristic is the seam Phase 6's Dynamic
   Profiles replace.
7. **`MemoryNote` is the realised `MemoryFact`.** Rather than rename the model that
   Phases 1–2 already wired through curation, approval, retrieval, and the browser, the
   existing `MemoryNote` *is* the durable fact unit (gaining `isSensitive` + `origin`).
   The other PRD §9 types ship alongside it. A rename is mechanical if ever wanted.
8. **Curated candidates are persisted as unapproved notes, not held in memory.** "Queued
   for approval" is realised as a review inbox: candidates are written with
   `isUserApproved == false`, which the retrieval predicate and Spotlight indexer both
   exclude — so nothing curated reaches a prompt or the system index until the user
   approves. This keeps approval structural while giving the queue durability across
   launches and devices.
9. **In-turn retrieval stays on the deterministic SwiftData path; Spotlight is the
   system surface.** The chat turn retrieves via the synchronous `searchMemories` scorer
   (predictable, no async in the tool path), while the *same* approved facts are donated
   as `IndexedEntity`s so Spotlight/Siri/Shortcuts can retrieve them attributably. This
   adopts Apple's Spotlight-powered RAG without guessing at the exact private
   FoundationModels Spotlight-tool API, which can't be verified without a device.
10. **CloudKit is enabled with a documented provisioning prerequisite.** The
    entitlement (`iCloud.com.charlesamaya.llmchat`) and `remote-notification` background
    mode are committed, and the container falls back to local-only at runtime if the
    capability is absent — so unsigned simulator/CI builds pass unchanged. The **next
    signed TestFlight archive** requires the iCloud container enabled on the App Store
    Connect app id and the `match` provisioning profiles regenerated to include it,
    otherwise `xcodebuild archive` signing fails.

-----

## A. How Claude Code should use this document

1. **Work one phase at a time, top to bottom.** Each phase is a shippable unit with explicit **Acceptance Criteria**. Do not start a phase until the previous phase’s criteria pass on a real device via TestFlight.
1. **Each phase section gives you three things, by design:** *Product requirements* (what/why for the user), *Apple-native technical approach* (how, with specific APIs and file paths), and *Why* (the rationale, so you can make good local decisions when the spec is silent).
1. **Respect the global guardrails in §B.** They encode platform constraints that are easy to violate and expensive to retrofit (CloudKit modeling, the 4K context budget, App Review code-execution rules).
1. **Commit per phase**, with the phase number in the message. Keep PRs phase-scoped.
1. **When the on-device model’s behavior is uncertain, write an eval** (Evaluations framework, set up in Phase 4) rather than guessing — this is a small model with a hard context limit; measure, don’t assume.
1. **Prefer Apple’s built-in primitives over custom infrastructure** every time there’s a choice. The platform now ships RAG, OCR, tool-calling, structured output, and provider routing — building our own is wasted effort and usually worse.

-----

## B. Global engineering principles & guardrails (apply to every phase)

**Architecture**

- **On-device first.** Default all reasoning to `SystemLanguageModel.default`. PCC is an explicit escalation; third-party cloud is opt-in/premium only. Never silently send personal data off device.
- **Approval before mutation.** Any tool that changes state (calendar, reminders, contacts, health, messages, memory writes, sends) must route through the central `ApprovalGate` and get explicit user confirmation. No exceptions.
- **Availability gating.** Every AI-dependent path checks `SystemLanguageModel.availability` and degrades gracefully (functional non-AI fallback or a clear “needs Apple Intelligence” state). Required for App Review and older devices.
- **Context budget discipline.** The on-device window is a **fixed 4096 tokens** holding instructions + tools + retrieved memory + transcript + input + response headroom. Measure with `tokenCount(for:)`; summarize at ~70% of `contextSize`; recover from `.exceededContextWindowSize` by re-seating the session.

**Hard “DO NOT” list**

- ❌ Do **not** build a custom vector database or embedding store. Use the FoundationModels **Spotlight-powered search tool** + App Intents entity schemas for local RAG.
- ❌ Do **not** use `SFSpeechRecognizer`. Use `SpeechAnalyzer` + `SpeechTranscriber`.
- ❌ Do **not** use SiriKit / `INIntent`. Use **App Intents** (SiriKit is deprecated).
- ❌ Do **not** generate or execute arbitrary code as “skills” (violates App Review §2.5.2). Skills are **declarative App Intent compositions** only.
- ❌ Do **not** put `@Attribute(.unique)` on, or use non-optional/non-defaulted properties in, any CloudKit-synced `@Model`. (CloudKit mirroring forbids it; retrofitting is painful.)
- ❌ Do **not** default to PCC or third-party providers, and do **not** push unsolicited notifications. Proactivity surfaces **in-app**; only user-approved routines may notify.
- ❌ Do **not** block the UI on model calls; stream and reflect `isResponding`.

**Concurrency:** Swift 6 strict concurrency. Sessions/transcripts are isolated; types crossing actor boundaries are `Sendable`; serialize to one in-flight request per session.

-----

## C. Build & deploy pipeline (no-Mac, bleeding-edge APIs) — set up in Phase 0

**Goal:** every merge to `main` produces a TestFlight build the developer installs on their phone. This is the foundation; nothing else is testable without it.

**Approach**

- GitHub Actions, `runs-on: macos-26` (or latest available). Steps: checkout → select Xcode → resolve SPM (cached) → `xcodebuild archive` → `-exportArchive` with `ExportOptions.plist` → upload to TestFlight.
- **Signing without a Mac:** use **App Store Connect API key** (Issuer ID + Key ID + `.p8`, stored as base64 GitHub secrets) for upload, and **`fastlane match`** (cloud-stored signing assets in a private git repo) for certificates/profiles. Alternative: cloud-managed signing via the API key.
- **Upload:** `fastlane pilot upload` or `xcrun altool --upload-app` with the API key.

**⚠️ The #1 pipeline risk for this project:** these features need **Xcode 27 / the iOS 26.4+ SDK**, and GitHub’s hosted runners often lag the newest Xcode. Mitigations, in order of preference: (1) pin to a runner image that already includes the required Xcode; (2) install the needed Xcode on the runner with `xcodes` (needs Apple auth + adds minutes); (3) evaluate **Xcode Cloud** as the CI instead (Apple-native, always has current Xcode, but initial setup assumes some Xcode access). **Claude Code: detect and surface the available Xcode/SDK version early; if it can’t satisfy the FoundationModels WWDC26 APIs, stop and flag it rather than silently targeting older APIs.**

**Acceptance:** a trivial commit triggers a build that lands in TestFlight and launches on device.

-----

## D. Repository structure (create in Phase 0, grow over phases)

```
Otto/
├── OttoApp/                         # app target: entry point, DI, app-level navigation
├── Packages/                        # local SPM packages (keep domains isolated + testable)
│   ├── AgentKit/                    #   ConversationEngine, ContextBudget, ModelRouter, PersonaStore, ApprovalGate
│   ├── MemoryKit/                   #   SwiftData @Models, MemoryManager, retrieval, CloudKit config
│   ├── ToolsKit/                    #   Tool-protocol implementations + dynamic tool selection
│   ├── SkillsKit/                   #   App Intents, AppShortcutsProvider, Dynamic Profiles, routines
│   └── VoiceKit/                    #   SpeechAnalyzer pipeline + AVSpeechSynthesizer
├── Features/                        # SwiftUI feature modules
│   ├── Chat/  MemoryBrowser/  Suggestions/  Briefing/  Onboarding/  Settings/
├── EvalHarness/                     # Evaluations-framework target (Phase 4+)
├── fastlane/                        # match + pilot config
└── .github/workflows/testflight.yml
```

**Why modular SPM packages:** keeps the context-budget/memory/tools logic unit-testable without the UI, lets Claude Code reason about one domain at a time, and prevents the agent loop from depending on view code.

-----

# PHASES

> Dependency order is strict P0→P8. Phases 0–3 build the spine and the hero (memory). Phases 4–8 add scale, personalization signals, self-improvement, surfaces, and ship.

-----

## Phase 0 — Skeleton, availability gating, and CI to device

**Product requirements.** Nothing user-facing yet except proof of life: the app installs from TestFlight, launches, checks whether Apple Intelligence is available, and completes one on-device model round-trip (“say hello”). This exists so every later phase is testable on real hardware.

**Apple-native technical approach.**

- Create the Xcode project + the SPM package skeleton in §D. SwiftUI lifecycle, Swift 6 language mode.
- Add `FoundationModels`. Implement an `AvailabilityService` wrapping `SystemLanguageModel.availability` (cases: available / unavailable-device / AI-disabled / model-not-ready) and surface a friendly state.
- One screen: a button that runs `let session = LanguageModelSession(); let r = try await session.respond(to: "Say hello")` and prints the result. Gate on availability; show the fallback state otherwise.
- Stand up the CI/CD pipeline in §C end-to-end.

**Why.** The developer has no Mac, so the CI→TestFlight loop *is* the development environment — it must exist before anything else. Availability gating is introduced first because it wraps every future AI call; building it once now avoids scattering checks later. The hello-world round-trip validates the SDK, entitlements, and device capability in isolation, before any complexity.

**Deliverables:** project + packages compiling; `AvailabilityService`; one working on-device call; green CI to TestFlight.
**Acceptance:** trivial commit → TestFlight build → app launches → “Say hello” returns model text on a capable device, and shows the graceful fallback on a simulator/unsupported path.
**Guardrails:** confirm the runner’s Xcode/SDK supports the FoundationModels APIs (§C warning) before proceeding.

-----

## Phase 1 — Conversation core: streaming chat, persona, context budget, persistence

**Product requirements.** A competent **cold-start** assistant: the user types (or, later, speaks) and gets a streaming, on-device response in a persona that’s consistent and concise. Conversations persist across launches. One real, useful action works end-to-end — creating a reminder — with an approval step before it’s written. This is the “useful to a stranger with zero personalization” milestone.

**Apple-native technical approach.**

- `AgentKit.ConversationEngine`: owns a `LanguageModelSession`, drives turns, dispatches tools, persists transcript to SwiftData.
- **Streaming UI:** use `session.streamResponse(...)`; bind the emitted `T.PartiallyGenerated` snapshots to SwiftUI `@State`. Declare `@Generable` response types with properties **in display order** (the model fills them in that order). Reflect `session.isResponding`; call `prewarm()` when the input field focuses.
- **PersonaStore:** persona/system prompt injected as session `instructions`. Keep it compact (it’s billed against the 4K window).
- **ContextBudget** (critical): read `model.contextSize`; measure prompts with `tokenCount(for:)`. Maintain a ring-buffer transcript; at ~70% utilization, run a separate short `@Generable` summarization call and replace old turns with the summary. Catch `.exceededContextWindowSize` and re-seat a fresh session seeded with the summary.
- **First tool:** `ToolsKit.CreateReminderTool` conforming to the `Tool` protocol (`description` + `@Generable Arguments` + async `call`). Route the actual write through `AgentKit.ApprovalGate`, which pauses for explicit user confirmation before calling EventKit/Reminders.
- Persist `Conversation`/`Message` via SwiftData (local only this phase — no CloudKit yet).

**Why.** Streaming via partial snapshots (not raw tokens) is the idiomatic FoundationModels pattern and makes a 3B model *feel* responsive despite limited speed. The context-budget manager is built **now, not later**, because the 4K window is the defining constraint of the whole product — every subsequent feature competes for that budget, so the discipline has to be in the spine. Guided generation (`@Generable`) is used from the first response so we never write fragile text parsers. The approval gate is introduced with the very first mutating tool so “approve before mutation” is structural, not bolted on.

**Deliverables:** streaming chat; persona; `ContextBudget` with summarization + error recovery; `ApprovalGate`; reminder tool; persistent conversations.
**Acceptance:** a multi-turn conversation survives relaunch; asking for a reminder shows an approval prompt and (on approval) creates it in Reminders; a long conversation triggers summarization without crashing.
**Guardrails:** measure tokens before every send; one in-flight request per session; no state writes without the gate.

-----

## Phase 2 — Tool library, multimodal capture, and dynamic tool selection

**Product requirements.** The assistant can *do things* across the user’s apps and *understand what they show it*: read the calendar, look up a contact, fetch a web page, and accept a photo/screenshot (“what’s this receipt total?”, “add this event from the screenshot”). Every action that changes something still requires approval.

**Apple-native technical approach.**

- Expand `ToolsKit` with `Tool`-conforming wrappers: EventKit (read calendar / propose events), Contacts (read), MapKit (lookups), a `URLSession` web-fetch tool, Files. Writes go through `ApprovalGate`; reads don’t.
- **Multimodal:** accept images into the session (WWDC26 image input). Prefer the **built-in `OCRTool` and `BarcodeReaderTool`** (Vision-backed) to convert images to compact text *before* feeding the model, to conserve the 4K budget; reserve raw image input for genuine visual reasoning.
- **Dynamic tool selection:** do not hand the model every tool each turn (tool definitions cost tokens). Implement a lightweight pre-step that selects only the tools plausibly relevant to the user’s input and includes just those in the session. (This is the precursor to Dynamic Profiles in Phase 6.)
- Observe `session.transcript` to render tool-call “cards” in the chat UI.

**Why.** An executive assistant is defined by the actions it can take, so the tool layer is the product’s hands. OCR/barcode are used to pre-digest images because a raw screenshot can consume a large share of 4096 tokens — turning it into text first is how multimodal stays viable on-device. Dynamic tool selection directly buys back context budget: fewer tool definitions per turn means more room for memory and conversation, which matters enormously at 4K.

**Deliverables:** calendar/contacts/maps/web/files tools; image input + OCR/barcode pre-processing; dynamic tool selector; tool-call cards.
**Acceptance:** the assistant answers “what’s on my calendar tomorrow?”, extracts a total from a photographed receipt, and proposes (with approval) a calendar event parsed from a screenshot.
**Guardrails:** never expose more tools than needed per turn; reads vs. writes correctly classified for the gate.

-----

## Phase 3 — The memory loop (HERO): SwiftData + CloudKit, local RAG, “what you know about me”

**Product requirements.** The differentiator. The assistant builds a **durable, user-owned model of the person** — people, projects, preferences, recurring tasks — and uses it to personalize responses. The user can **see, edit, and delete everything** it remembers, and memory follows them across their devices. Nothing sensitive is curated into long-term memory without approval.

**Apple-native technical approach.**

- `MemoryKit` SwiftData `@Model` types: `MemoryFact`, `UserPref`, `Skill`, `SuggestedRoutine`, `PreferencePair`, `StreamlineGrant` (per PRD §9). **CloudKit constraints baked in from the first commit:** all properties optional or defaulted; **no unique constraints**; relationships optional with inverses.
- **Sync:** `ModelConfiguration` bound to a **CloudKit private database** container; verify mirroring on a second device.
- **Curation:** a `MemoryManager` runs an on-device summarization pass over recent turns to distill candidate `MemoryFact`s; **sensitive/uncertain facts are queued for approval** rather than written silently.
- **Retrieval (local RAG, no vector DB):** use the FoundationModels **Spotlight-powered search tool** for on-device retrieval. Contribute `MemoryKit` entities to the **Spotlight semantic index via App Intents entity schemas** so retrieval is system-native and attributable. Inject only top-k relevant facts per turn (feeds the ContextBudget from Phase 1).
- **“What you know about me” screen** (`Features/MemoryBrowser`): browse/edit/delete any fact, preference, or routine; full export + “forget me” delete.

**Why.** This is the moat and the retention engine — switching cost grows with accumulated, *legible* memory. It’s built on SwiftData+CloudKit because that keeps personal data on-device and in the user’s *private* iCloud (the core privacy claim) with zero server cost. We deliberately use Apple’s Spotlight-powered RAG instead of a custom vector store: it’s less code, it’s maintained by Apple, and routing memory through App Intents schemas means the system (and the new Siri) can use it too. Approval-gated curation is what separates “helpful memory” from “creepy surveillance,” which is a stated product principle. The CloudKit modeling rules are enforced from commit one because changing a shipped schema to satisfy them later is a migration nightmare.

**Deliverables:** memory models + private CloudKit sync; approval-gated curation; Spotlight RAG retrieval wired into the turn loop; memory-browser UI with edit/delete/export.
**Acceptance:** state a fact in one session; in a later session (and on a second device) the assistant recalls and applies it; the user can edit/delete it in the browser and the change takes effect.
**Guardrails:** CloudKit modeling rules; never auto-write sensitive memory without approval; inject only top-k, never the whole store.

-----

## Phase 4 — Model routing, PCC escalation, and the Evaluations harness

**Product requirements.** Hard tasks (synthesizing a week, multi-step reasoning) get noticeably better answers, while everyday tasks stay instant, free, and private — and the user never has to think about which model ran. We also gain the ability to *prove* where the small model is good enough.

**Apple-native technical approach.**

- `AgentKit.ModelRouter` behind the WWDC26 **`LanguageModel` protocol**. Tiers: on-device (`SystemLanguageModel.default`) → **`PrivateCloudComputeLanguageModel()`** (32K window, reasoning; no API keys/auth needed) → optional third-party provider (Claude/Gemini via SPM, opt-in). The call site is identical across tiers; only the injected model changes.
- **Routing policy** (`RoutingPolicy` in SwiftData): per-task-kind tier preference, an “offline-only/on-device-only” toggle, and (later) a spend ceiling for third-party. Personal/sensitive context biases toward on-device/PCC; PCC respects its **daily per-user limit** (fall back to on-device when exhausted).
- **Fallback chain** with graceful degradation; surface which tier answered (transparency).
- Stand up the **`EvalHarness`** using Apple’s **Evaluations framework**: build eval sets for the real assistant tasks; quantify on-device vs PCC quality and the effect of context strategies.

**Why.** This phase exists because of the 4K ceiling: some tasks simply don’t fit or need real reasoning, and PCC’s 32K window + reasoning is the escape hatch — but it’s rate-limited and is the one place data leaves the device, so it must be a deliberate, policy-driven escalation rather than a default. Hiding all of this behind the `LanguageModel` protocol means the rest of the codebase never changes when providers change. The Evaluations harness is non-negotiable for a small model: it converts “which model should run this?” from a guess into a measured decision, which directly determines free-tier load, latency, and cost.

**Deliverables:** `ModelRouter` + `RoutingPolicy` + fallbacks; PCC integration; eval harness with initial task evals; per-tier transparency in UI.
**Acceptance:** the same conversation runs on on-device and PCC by policy with no call-site changes; PCC exhaustion falls back cleanly; an eval report shows the on-device/PCC quality boundary for representative tasks.
**Guardrails:** on-device default; third-party never without explicit opt-in; reasoning tokens counted against PCC’s 32K.

-----

## Phase 5 — Preference learning + opt-in proactivity (suggested routines + briefing)

**Product requirements.** Two things make the assistant feel like *yours*: it learns your taste, and it gets helpfully (never invasively) proactive. (1) The **preference picker**: occasionally it offers two response variants and you tap the one you like. (2) **Suggested routines**: it quietly notices patterns and proposes turning them into routines *inside the app*; you approve/edit/dismiss. Only approved routines (e.g., a morning briefing) ever notify you.

**Apple-native technical approach.**

- **Preference picker** (`Features/Suggestions`): generate two variants via differing `GenerationOptions` (length/temperature) or two instruction deltas; store the pick as a `PreferencePair`; fold the winning style into `UserPref` + the persona instructions. Strict frequency cap; always skippable; all on-device.
- **Pattern detection → suggestions:** on-device analysis proposes `SuggestedRoutine`s surfaced in an **in-app inbox** (never a push). On approval, register the routine.
- **Briefing & scheduling:** approved routines register `BGTaskScheduler` work (`BGAppRefreshTaskRequest` light / `BGProcessingTaskRequest` heavy); generate the brief on-device (escalate to PCC only if needed); deliver via `UNUserNotificationCenter`. Dismissals are a negative signal that suppresses similar future suggestions.

**Why.** The preference picker is a low-effort, on-device way to collect *explicit* taste signal (and, later, adapter-training data) without sending anything to a server — privacy-preserving personalization. Proactivity is deliberately re-architected as **propose-then-approve** because unsolicited notifications are the fastest way to get an assistant muted or deleted; making approval structural (suggestions in-app, only approved routines notify) turns the biggest churn risk into a trust feature. `BGTaskScheduler` is the only native path for unattended work, with the honest caveat that it’s best-effort, not cron.

**Deliverables:** preference picker + `PreferencePair` pipeline; suggestion inbox; approval→routine registration; on-device briefing via BGTask + notifications.
**Acceptance:** picks measurably shift response style; a suggested routine, once approved, runs and notifies; dismissing a suggestion suppresses similar ones; no notification ever appears without prior approval.
**Guardrails:** no unsolicited push; frequency caps on the picker; routines editable/pausable from the memory browser.

-----

## Phase 6 — Skills & subagents: declarative routines + Dynamic Profiles

**Product requirements.** The assistant assembles **reusable, named routines** from things you repeat (“my travel prep”, “my Monday review”), runs multi-step work reliably, and can split focused work (e.g., a “research” mode) from the main conversation. Routines self-improve from whether they worked — but never by writing code.

**Apple-native technical approach.**

- Model a `Skill` as a **declarative composition of `AppIntent`s** (a recipe in SwiftData), exposed through an `AppShortcutsProvider`. Adopt **App Intents schemas** so routines are discoverable by Siri/Spotlight/Shortcuts. Track `runCount`/`successRate` and let the assistant *propose revisions* (approval-gated).
- Use **Dynamic Profiles** (`DynamicProfile` protocol; a `body` returning a `Profile` of instructions + tools) to switch modes within a single `LanguageModelSession` and to manage context (transcript trim/summarize, KV caching). Use the framework’s orchestration patterns (“phone-a-friend”, “baton-pass”) for local↔PCC handoffs and for subagent-style parallel work.

**Why.** This is the Hermes “self-improvement” loop, made App-Store-legal: skills are declarative intent compositions, **not** generated code (App Review §2.5.2 forbids the latter). Building skills on App Intents means they’re simultaneously the mechanism for Siri discoverability — one abstraction, two payoffs. Dynamic Profiles replace hand-rolled subagent/context plumbing with a first-class declarative API that *also* handles transcript trimming and KV caching, which is exactly the context-budget work we’d otherwise do manually at 4K.

**Deliverables:** declarative `Skill` model + App Intents exposure; self-improvement (proposed revisions); Dynamic Profiles for modes + subagents.
**Acceptance:** the assistant proposes a routine the user didn’t manually configure; once approved it runs end-to-end and is invocable from the Shortcuts app; a “research” profile runs without polluting the main chat context.
**Guardrails:** no code generation/execution; revisions are approval-gated; App Intents schemas adopted (not SiriKit).

-----

## Phase 7 — Voice & system-surface invocation

**Product requirements.** The user can talk to the assistant and invoke it from anywhere in the OS — Siri, the Action button, Spotlight, Shortcuts — not just inside the app.

**Apple-native technical approach.**

- **STT:** `Speech` framework’s **`SpeechAnalyzer`** with a **`SpeechTranscriber`** module (on-device; add `SpeechDetector` for voice-activity). Manage language assets via `AssetInventory` (download proactively for instant first use). **Locale gotcha:** resolve locales with `SpeechTranscriber.supportedLocale(equivalentTo:)`, not `Locale.current` directly. Pipe transcript → ConversationEngine.
- **TTS:** `AVSpeechSynthesizer`.
- **System invocation:** the assistant’s core actions are already `AppIntent`s (Phase 6); register an `AppShortcutsProvider` so they’re reachable via Siri/Action button/Spotlight, and confirm the app is visible to the new Siri (apps without App Intents are invisible to it).

**Why.** Voice and system invocation are what make it feel like an assistant rather than a chat app, and Apple’s native STT (`SpeechAnalyzer`, the on-device replacement for `SFSpeechRecognizer`) keeps the privacy story intact — no audio leaves the device. Reusing the Phase-6 App Intents for invocation means we get OS-wide reach without new surface-specific code; it also keeps us discoverable by the system assistant rather than competing as a walled garden.

**Deliverables:** on-device STT pipeline with asset handling; TTS; Siri/Action-button/Spotlight/Shortcuts invocation.
**Acceptance:** a spoken request is transcribed on-device and answered (aloud, if voice mode is on); the assistant runs from a Siri phrase and from the Action button.
**Guardrails:** no `SFSpeechRecognizer`; handle missing language assets and locale mismatches gracefully.

-----

## Phase 8 — Premium, onboarding magic moment, and public beta

**Product requirements.** First-run earns trust in 60 seconds, and the business model is live. Onboarding produces an immediate personalized “this already gets me” moment; a premium tier unlocks cloud-grade reasoning and richer automation; the app is ready for an external TestFlight beta.

**Apple-native technical approach.**

- **Onboarding magic moment** (`Features/Onboarding`): after permission grants, run an on-device pass over already-available data (today’s calendar/reminders) to produce one strikingly relevant observation. Request permissions progressively, with clear value framing.
- **Premium:** StoreKit 2 subscription gating the third-party-cloud routing tier (Phase 4), richer proactivity, and any cross-device extras. Keep the **free tier sustainable on-device-only** so paid = cloud.
- **Beta:** external TestFlight group; wire lightweight, privacy-respecting metrics for the PRD’s north star (personalization depth × retention) — activation, preference-picker participation, suggestion approval rate, routine-pause rate.

**Why.** Cold-start credibility is an existential risk for a personalization product — if day one feels generic, users churn before the loop pays off — so the onboarding moment, built from data already on the device, is worth disproportionate effort. Monetization is structured around the actual cost curve: on-device is free to us, so the paywall sits at the metered cloud boundary, keeping the free tier durable past the PCC free-tier cliff. StoreKit 2 is the only native path for subscriptions.

**Deliverables:** onboarding flow + magic moment; StoreKit 2 premium gating cloud tier; metrics; external beta.
**Acceptance:** a new user hits a personalized moment within ~60s of granting permissions; subscribing unlocks the cloud tier; metrics report the activation and personalization signals.
**Guardrails:** free tier never silently uses paid cloud; metrics privacy-respecting; permissions requested with justification, not up front in a wall.

-----

## E. Cross-cutting backlog (track continuously, not a phase)

- **Evaluations** expand every time a routing or context-engineering decision is made (data, not vibes).
- **Accessibility & localization** from Phase 1 UI onward.
- **Error taxonomy & telemetry** for model errors (`.exceededContextWindowSize`, unsupported locale, availability changes, PCC limit).
- **Privacy review** before beta: confirm no personal data path leaves the device except explicit PCC/third-party escalations; verify export + “forget me”.
- **App Review pre-check:** §2.5.2 (no code execution), availability fallback present, permission justifications, subscription compliance.

## F. Forward-looking (post-PMF, not in scope now)

- Per-user **on-device personalization adapter** trained from accumulated `PreferencePair` data, once FoundationModels open-sources (summer 2026) / via Core AI. This would make “grows with you” literal.
- Optional **developer/power-user skills** (the §16 extra), possibly bridging to an external Hermes server for code-exec tasks — strictly opt-in, never in the consumer core.