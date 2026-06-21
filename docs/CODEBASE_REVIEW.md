# Claw (native-claw) — Codebase Review, UX Test Plan & Plan Evaluation

> Review of the repository as of branch `claude/codebase-review-requirements-lnlojr`.
> Companion tracked issues: #27 (CloudKit provisioning), #28 (StoreKit products).

## Context

This is a **review/audit document**, not a feature build. It walks through the features,
sanity-checks them with a UX test plan (verified where possible), calls out gaps +
remediation, and evaluates the result against `IMPLEMENTATION_PLAN.md`.

**Note on verification scope:** Claw is a native **iOS 26 / Apple Intelligence** app
(Swift 6, SwiftUI, SwiftData, FoundationModels, EventKit, MapKit, Speech, CloudKit,
StoreKit 2). It cannot be built or run on a Linux host — no Xcode, no simulator, no Apple
Intelligence. Runtime UX testing requires a Mac + an Apple-Intelligence device. What was
verifiable without one is recorded below.

---

## What the app is

**Claw** (target `LLMChat`) — a privacy-first, on-device personal assistant. One agent,
all inference on-device via Apple's Foundation Models, everything persisted in SwiftData,
nothing leaves the device by default. Modular XcodeGen framework targets:

- **MemoryKit** — SwiftData `@Model`s, persistence, retrieval, Spotlight, routing policy, metrics
- **ToolsKit** — `Tool`-protocol implementations + dynamic tool selection
- **AgentKit** — `ConversationEngine`, `ContextBudget`, `ApprovalGate`, `ModelRouter`, persona, preference/proactivity
- **SkillsKit** — declarative skills, App Intents, Shortcuts
- **VoiceKit** — `SpeechAnalyzer` STT + `AVSpeechSynthesizer` TTS
- **EvalHarness** — deterministic eval suite + runner
- **LLMChat (App)** — entry point, `ContentView` gate, feature views

63 Swift files. Navigation gate (`ContentView`): availability → onboarding (no persona) → chat.

---

## Verification status (what was actually checked)

| Check | Method | Result |
|---|---|---|
| App compiles against real iOS 26 SDK + FoundationModels | GitHub Actions `build.yml` on `main` + all phase PRs | ✅ **green** |
| Release archive (unsigned, device) builds | CI `archive_check` lane (blocks PRs) | ✅ **green** |
| Features are wired, not stubbed | Static read of `ConversationEngine`, `ModelRouter`, etc. | ✅ real implementations |
| No dead/unimplemented paths | Grep `TODO/FIXME/unimplemented/fatalError` | ✅ only legitimate FM/Vision fallbacks |
| Runtime UX (streaming, approvals, memory recall, voice…) | **Requires Mac + device** | ⛔ not verifiable off-device |

---

## Feature walkthrough + UX test plan

Each feature: where it lives → manual test → expected → verification status.
Status legend: 🟢 compiles+wired (CI/static) · 🔵 needs device to confirm runtime.

### 1. Availability gating (Phase 0)
`AvailabilityService` · `AvailabilityUnavailableView` · `ContentView`
- **Test:** Run on a non-AI device / AI disabled / model still downloading.
- **Expect:** Friendly fallback screen with the specific reason + next steps; no crash. 🟢🔵

### 2. Onboarding → Persona (Phase 1)
`OnboardingView(Model)` · `ConversationEngine.startOnboarding/extractPersona` · `PersonaStore` · `PersonaView`
- **Test:** First launch → have the casual shaping chat → confirm persona; later open Persona to view/edit.
- **Expect:** A `Persona` is produced through conversation alone (name/vibe/values/expertise) and folds into every session's instructions. 🟢🔵

### 3. Streaming chat (Phase 1)
`ChatView` · `ChatViewModel` · `ConversationEngine.streamResponse`
- **Test:** Send a message; watch tokens stream; relaunch app mid/after conversation.
- **Expect:** Partial-snapshot streaming bound to SwiftUI; controls gated on `isResponding`; **conversation survives relaunch** (SwiftData persist). 🟢🔵

### 4. Approval gate + confirmation cards (Phase 1, safety-critical)
`ApprovalGate` · `ConfirmationCards` · `DraftTypes` · `CreateReminderTool`
- **Test:** "Remind me to call Sam at 5pm." Then **deny** once, **approve** once.
- **Expect:** A reminder card appears; **nothing is written** until you tap approve; on approve it lands in Reminders (EventKit). No mutation path bypasses the gate. 🟢🔵

### 5. Context budget / summarization (Phase 1)
`ContextBudget` · `ConversationEngine.reseatWithSummary`
- **Test:** Drive a long conversation past ~70% of the 4K window.
- **Expect:** Proactive summarize + session re-seat; typed `exceededContextWindowSize` recovery; **no crash**. 🟢🔵

### 6. Tool library (Phase 2)
`CalendarTools` · `ContactsTool` · `MapsTool` · `WebFetchTool` · `ToolRegistry` · `ToolSelector`
- **Test:** "What's on my calendar tomorrow?" / "Look up Alex's number" / "Find coffee near me" / "Summarize <url>".
- **Expect:** Read tools answer directly; `createCalendarEvent` is approval-gated; tool chips show what ran; `ToolSelector` only attaches relevant tools (lazy grow + re-seat). 🟢🔵

### 7. Multimodal capture (Phase 2)
`ImageProcessor` (Vision OCR + barcode), PDFKit
- **Test:** Attach a receipt photo ("what's the total?"), a screenshot of an event ("add this"), a PDF.
- **Expect:** On-device OCR → **text digest** folded into the turn (not raw pixels, to protect 4K budget); event becomes an approval-gated draft. 🟢🔵
  *(Raw-image visual reasoning is a documented WWDC26 seam — text digest only today.)*

### 8. Memory loop — the hero (Phase 3)
`MemoryManager.curate` · `MemoryStore` · `MemoryBrowserView` · `MemorySpotlight` · `MemoryContainer` (CloudKit)
- **Test:** State a durable fact ("I'm vegetarian"); a few turns later open Memory → Review; approve it; ask something that should use it in a **later session**; check recall on a **second device**.
- **Expect:** Curated facts land **unapproved** in a review inbox (never injected/indexed until approved); sensitive items never auto-approve; approved facts personalize later turns and **sync via private CloudKit**; browser supports edit / forget / export / wipe-all. 🟢🔵
  *(CloudKit sync requires the provisioning step in #27 — see Gap G2.)*

### 9. Model routing + transparency (Phase 4)
`ModelRouter` · `RoutingPolicy` · `RoutingSettingsView` · `ModelTier`/`TaskKind`
- **Test:** Toggle on-device-only lock; set PCC daily limit; send a reasoning/oversized prompt; read the per-turn tier chip; run the on-demand eval.
- **Expect:** Policy resolves a tier (lock wins; size/over-budget escalates to PCC; PCC metered daily); **chip honestly shows the *bound* tier**. Today every turn is *bound* to on-device with a visible "PCC binding pending device" reason (intentional seam). 🟢🔵

### 10. Evaluations harness (Phase 4)
`AssistantEvalSuite` · `EvalRunner` · `EvalTypes`
- **Test:** Trigger eval from routing settings.
- **Expect:** Greedy-sampled tasks (extraction/classification/summarization/reasoning) graded deterministically; pass-rate + latency for on-device; cloud tiers reported as "pending binding." 🟢🔵
  *(Not wired into CI — see Gap G1.)*

### 11. Preference learning (Phase 5)
`PreferenceLearner` · `PreferenceChoiceCard` · `UserPref`
- **Test:** Chat normally; occasionally (≤ every 6h) you'll get an A/B card; pick one; observe later style.
- **Expect:** Two variants of *your real answer* differing on one axis (length/warmth), off the streaming path; pick stored as `UserPref`, session re-seated so style shifts immediately; always skippable. 🟢🔵

### 12. Proactivity: suggestions + briefing (Phase 5)
`RoutineSuggester` · `SuggestionInboxView` · `ProactivityScheduler` · `BriefingService`
- **Test:** Use recurring patterns; open Suggestions; approve a routine (grants notifications); dismiss another; wait for a background brief.
- **Expect:** Routines proposed into an **in-app inbox (never a push)**; dismissals are durable negatives; **only approved routines schedule/notify**; brief = today's calendar + top memories via `.backgroundTask(.appRefresh:)`. 🟢🔵
  *(iOS decides if/when background refresh fires — inherent caveat.)*

### 13. Skills & subagents (Phase 6)
`SkillCatalog` · `SkillRunner` · `SkillStore` · `SkillIntents`/`ClawShortcuts` · `SkillsView` · `ConversationProfile` (research)
- **Test:** Approve a suggested skill; run it; invoke from Siri/Spotlight/Shortcuts; toggle Research mode and chat.
- **Expect:** Skills are **declarative recipes over a closed action vocabulary** (no generated code — App Review §2.5.2 safe); approved skills run on-device + are Siri/Shortcuts-invocable; **research mode is an isolated subagent** (baton-passed summary, restricted tools, never pollutes main chat). 🟢🔵

### 14. Voice I/O (Phase 7)
`VoiceTranscriber` (SpeechAnalyzer) · `SpeechSpeaker` (AVSpeechSynthesizer) · `AskClawIntent`/`AssistantQuickResponder`
- **Test:** Tap mic to dictate; enable "Speak replies"; invoke "Ask Claw…" from Siri/Action button.
- **Expect:** On-device STT mirrors live into the field; final reply read aloud; out-of-app invocation is a **read-only, no-tools, nothing-persisted** one-shot (structurally can't mutate). All on-device. 🟢🔵

### 15. Premium / paywall (Phase 8)
`PremiumStore` (StoreKit 2) · `PremiumEntitlement` · `PaywallView`
- **Test:** Open paywall; (sandbox) subscribe; confirm third-party cloud tier unlocks in routing.
- **Expect:** Free tier fully usable on-device + PCC; subscription flips the `PremiumEntitlement` gate `ModelRouter` reads. Shows "unavailable" cleanly if products aren't configured (they aren't yet — Gap G3, #28). 🟢🔵

### 16. Onboarding magic moment + metrics (Phase 8)
`MagicMomentService` · `UsageCounter`/`Metrics`
- **Test:** Fresh onboarding with calendar/reminders access; check "Your usage" settings.
- **Expect:** One strikingly relevant on-device observation from *today's* data (degrades silently if denied/empty); content-free north-star counters (activation, picker offered/answered, suggestion approval, routine pause) — **no analytics SDK, no network**. 🟢🔵

---

## Gaps & remediation

### Real, actionable gaps (not intentional seams)

**G1 — No automated tests; EvalHarness not gated in CI. (Highest priority.)**
There are **zero XCTest/Swift Testing targets** (the Fastlane `test` lane has nothing to run),
and `EvalHarness` isn't run in CI. Much of the highest-risk logic is **pure and
device-independent** and should be tested without Apple Intelligence:
- `ModelRouter.applyPolicy/bind` (privacy lock precedence, size escalation, PCC budget exhaustion, premium gating, degraded reasons)
- `RoutingPolicy` (singleton load, daily PCC budget rollover/consume)
- `ContextBudget` (token estimate, ~70% summarize threshold, response headroom)
- `ToolSelector` (keyword → tool-set selection; memory-tools-always-on)
- `ApprovalGate` (no write without confirm — the core safety invariant)
- `SkillCatalog`/recipe parsing (unknown actions drop gracefully)

**Remediation:** Add a `LLMChatTests` XcodeGen test target depending on AgentKit/MemoryKit/ToolsKit/SkillsKit; write unit tests for the above (they don't need a model). Add a CI job running the `test` lane on the simulator, and run `EvalHarness` (on-device tier) as a non-blocking report or smoke check. Wire into `build.yml` so regressions block PRs.

**G2 — CloudKit container not provisioned (blocks the next signed TestFlight archive).** *(Tracked: #27)*
The entitlement (`iCloud.com.charlesamaya.llmchat`) + `remote-notification` mode are committed
and the app falls back to local-only at runtime, but a **signed archive will fail** until the
iCloud container is enabled on the App Store Connect app id and the `match` profiles are
regenerated to include it. Cross-device memory sync (the hero promise) is also inert until then.
**Remediation:** Enable the iCloud container; regenerate `match` profiles; run `deploy.yml`; confirm sync across two devices. (Account-level — needs the owner.)

**G3 — Premium products not configured.** *(Tracked: #28)*
No App Store Connect subscription group/products, so `PaywallView` shows "unavailable" and the
third-party tier can never unlock.
**Remediation:** Create the subscription group + product IDs (and a StoreKit config file for sandbox testing); verify purchase → `PremiumEntitlement` flip → routing unlock.

**G4 — No UI/integration test for the approval-gate invariant.**
"No mutation without approval" is the product's central safety claim and is enforced only in
code. **Remediation:** add an integration test (or XCUITest) asserting that denying a
reminder/calendar/persona draft performs no EventKit/SwiftData write.

### Intentional seams (NOT bugs — deferred to the WWDC26 device SDK, all documented in the plan §Deviations)
- **Cloud-tier model binding** (PCC + third-party) degrades to on-device and is flagged (`degraded` + visible reason). One-function swap when the API is device-verifiable. (Dev. 11)
- **Raw image visual reasoning** — OCR-to-text digest today. (Dev. 5)
- **Real Evaluations framework + LLM grader** — deterministic keyword/structure grading today. (Dev. 13)
- **App Intents assistant schemas** (`@AssistantIntent`) — stable `AppIntent` surface today. (Dev. 20/23)
- **FoundationModels Spotlight-tool API** — deterministic SwiftData retrieval + `IndexedEntity` donation today. (Dev. 9)
- **Continuous voice (VAD/`SpeechDetector`)** — press-to-talk today. (Dev. 22)

These are honest, well-isolated, and the surrounding policy/UI/transparency already ship — they should **not** be "fixed" now.

---

## Evaluation vs. IMPLEMENTATION_PLAN.md

**Verdict: the plan was executed thoroughly and with unusual discipline.** All 8 phases are
built and every acceptance criterion is addressed in code; the build is CI-green against the
real SDK. The standout is **fidelity to the guardrails (§B)** — on-device-first, approval-
before-mutation, availability gating, and the 4K context-budget discipline are not slogans,
they're enforced at single chokepoints (`ApprovalGate`, `ModelRouter`, `ContextBudget`).

**Where it fully delivers the original aims:**
- Privacy-first on-device assistant with shaped persona, durable user-owned memory, approval-gated actions, tool use, voice, and system-surface reach — the complete product arc.
- The "hero" memory loop (curate → review/approve → personalize → sync) is real end-to-end (modulo the CloudKit provisioning step, #27).
- Honest transparency: the routing chip reports the *bound* tier, never overclaiming the cloud it can't yet bind.

**Where it intentionally stops short of the letter** (all 26 deviations are documented and
defensible, mostly "this WWDC26 API can't be compile-verified without a device, so ship the
policy + UI + a one-function seam"): cloud-tier bindings, raw-image input, the real
Evaluations framework, assistant schemas, the FM Spotlight tool API.

**The one real divergence from the plan's own spirit:** the plan repeatedly says *"measure,
don't assume — write an eval rather than guess"* (§A.5), yet there are **no automated tests
and EvalHarness isn't run in CI** (G1). For a phased, no-Mac, CI-to-TestFlight workflow, the
absence of a regression gate on the device-independent logic is the most meaningful gap
between the plan's intent and the delivered state.
