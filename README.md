# Claw — a private, on-device AI assistant

Claw is a native iOS app that gives you one personal AI agent powered entirely by
Apple's on-device **Foundation Models** framework. It runs fully on-device, stores
everything in SwiftData, has a personality you shape, remembers what you tell it
(only after you approve), and can act through tools. No server, no account, nothing
leaves the device.

This repository executes the phased build in
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md). The product spec is
[`CLAW_SPEC.md`](CLAW_SPEC.md); coding conventions for AI agents are in
[`CLAUDE.md`](CLAUDE.md).

## Status

| Phase | Scope | State |
|-------|-------|-------|
| **0** | Skeleton, availability gating, CI→TestFlight | ✅ built |
| **1** | Conversation core: streaming chat, persona, context budget, approval gate, first tools, persistence | ✅ built |
| **2** | Tool library, multimodal capture, dynamic tool selection | ✅ built |
| **3** | Memory loop: CloudKit sync, local RAG, "what you know about me" | ✅ built |
| **4** | Model routing, PCC escalation policy, Evaluations harness | ✅ built |
| **5** | Preference learning + opt-in proactivity (suggested routines + briefing) | ✅ built |
| **6** | Skills & subagents: declarative routines + Dynamic Profiles | ✅ built |
| 7–8 | Voice & system-surface invocation, premium + public beta | planned |

## Architecture

Domains are split into framework modules (IMPLEMENTATION_PLAN §D) so the agent
loop, memory, and tools are isolated from view code and independently buildable.

```
LLMChat/
├── project.yml                  # XcodeGen spec — defines all targets
├── Packages/
│   ├── MemoryKit/               # SwiftData @Models, drafts, ToolEvent, retrieval, RoutingPolicy
│   ├── ToolsKit/                # Tool implementations (memory tools + createReminder)
│   ├── AgentKit/                # AvailabilityService, PersonaStore, ContextBudget,
│   │                            #   ApprovalGate, ConversationEngine, ModelRouter
│   └── EvalHarness/             # assistant eval suite + runner (Phase 4)
├── App/                         # app target (product "Claw")
│   ├── LLMChatApp.swift         #   entry point + ModelContainer
│   ├── ContentView.swift        #   availability → onboarding → chat gate
│   └── Features/                #   Chat, Onboarding, MemoryBrowser, Persona, Availability
├── Resources/                   # Info.plist, asset catalog
└── fastlane/                    # match + pilot config
```

> **Module mechanism.** Modules are XcodeGen *framework targets* rather than
> separate `Package.swift` manifests. The whole project is driven by the single
> `project.yml` the CI already builds, every module inherits one deployment target
> (iOS 26), and boundaries are still enforced by the build system (`import
> MemoryKit`, `import AgentKit`, …). This avoids per-package platform wiring that
> can't be verified without a Mac.

### Key types

| Type | Module | Role |
|------|--------|------|
| `ConversationEngine` | AgentKit | Owns the `LanguageModelSession`, drives streaming turns, dispatches tools, persists the transcript. |
| `ContextBudget` | AgentKit | The 4K-window discipline — estimates usage, summarises at ~70%, re-seats the session on overflow. |
| `ApprovalGate` | AgentKit | The single chokepoint for every state-mutating action (memory, persona, reminders). Nothing is written without explicit confirmation. |
| `AvailabilityService` | AgentKit | Normalises `SystemLanguageModel.availability`; the UI gates on it. |
| `PersonaStore` | AgentKit | Builds the compact system instructions from the saved persona. |
| `buildTools` | ToolsKit | Assembles the tool set (search/save/update memory, persona, files, `createReminder`). |
| `ModelRouter` | AgentKit | Decides the model tier per turn (on-device → PCC → opt-in third-party) from `RoutingPolicy`, token pressure, and the PCC daily budget; surfaces which tier answered. |
| `EvalRunner` / `AssistantEvalSuite` | EvalHarness | Runs representative assistant tasks with greedy sampling and reports pass-rate + latency per tier, so routing is decided from data. |
| SwiftData `@Model`s | MemoryKit | `Persona`, `MemoryNote`, `ImportedFile`, `Conversation`, `Message`, `RoutingPolicy`, … |

## How it works

- **On-device only.** All inference uses `LanguageModelSession` with guided
  generation (`@Generable`). No external model APIs.
- **Streaming.** Responses stream as cumulative partial snapshots bound straight
  to SwiftUI state, so a small model still feels responsive.
- **Approve before mutation.** Tools never write directly — they propose a draft
  that surfaces as a confirmation card; the write happens only on your tap.
- **Context budget.** The fixed ~4K window is managed in the spine: usage is
  estimated each turn, the transcript is summarised before it overflows, and the
  session is re-seated from a condensed summary on `exceededContextWindowSize`.
- **Persona.** Onboarding is a short conversation that produces a structured
  `Persona`; it seeds the system instructions every session.

## Building (requires a Mac with Xcode 26+)

1. `brew install xcodegen`
2. From `LLMChat/`: `xcodegen generate`
3. Open `LLMChat.xcodeproj`, build the **LLMChat** scheme.
4. Run on a physical device with Apple Intelligence enabled. On the simulator the
   app launches and shows the graceful "Apple Intelligence required" fallback
   (on-device inference needs real hardware).

## CI/CD

GitHub Actions (no Mac required for the developer):

- **build.yml** — every push/PR: selects Xcode 26 (so `canImport(FoundationModels)`
  is true), runs `xcodegen generate`, builds the **LLMChat** scheme for the
  simulator (Debug), then archives it for a generic iOS **device** in **Release**
  (unsigned). The Release archive is a cheap proxy for the deploy: it catches
  Release-only compile/archive failures on the PR instead of letting them surface
  later in TestFlight.
- **generate.yml** — on `project.yml` changes to `main`: regenerates and commits the `.xcodeproj`.
- **deploy.yml** — manual/`workflow_dispatch` (against any branch) or tag push:
  signs via Fastlane Match and uploads to TestFlight, then publishes a
  `testflight/deploy` commit status on the head SHA so an automated run can
  observe the result.

The `.xcodeproj` is regenerated from `project.yml` on every CI run, so it does not
need to be committed by hand.

## Requirements

- Xcode 26+ / iOS 26 SDK (Foundation Models WWDC25 APIs)
- iOS 26 device with Apple Intelligence enabled
- Apple Developer account (device builds + TestFlight)
