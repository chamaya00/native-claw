# Claw — Project Spec v1.0

## What you are building

Claw is a native iOS app that gives the user one personal AI agent powered by Apple's Foundation Models framework. The agent runs fully on-device, stores all memory locally using SwiftData, and is accessible through a single chat interface. The agent has a personality, remembers what the user tells it, learns over time through approved memory writes, and can read files the user imports. Everything works offline.

The product feeling should be: a private, intelligent agent that actually remembers you, tries to help with what you describe, and gets noticeably better the more you use it.

***

## Core principles

- **Local-first.** No network calls, no third-party APIs, no cloud sync in v1. Everything runs on device.
- **Foundation Models only.** All AI inference uses Apple's `LanguageModelSession` and guided generation. No OpenAI, Anthropic, or other external model APIs.
- **SwiftData is the source of truth.** All persistent state — memories, persona, conversations, skills, imported files — lives in SwiftData. Markdown files are export artifacts only, never the runtime store.
- **Tool calling is how Claw acts.** The agent does not generate arbitrary actions. It can only call the tools the app defines. Every tool result flows back into the model context before the final response.
- **User approves writes.** Claw can propose memory saves and persona updates in chat, but durable writes only happen after explicit user confirmation ("Save this" or a confirm button).
- **Outcomes first.** The product should feel magical when tool calls compose well. Prefer fewer, powerful tools over many shallow ones.

***

## Tech stack

- **Language:** Swift, SwiftUI
- **AI:** `FoundationModels` framework (`LanguageModelSession`, `@Generable`, `Tool`)
- **Persistence:** SwiftData (`@Model`, `ModelContainer`, `ModelContext`)
- **Speech:** `AVSpeechSynthesizer` for optional spoken responses (post-MVP)
- **Files:** `UIDocumentPickerViewController` for local file import
- **Minimum target:** iOS 18.1, Apple Intelligence enabled device

***

## Data models

Define all of these as SwiftData `@Model` classes.

```swift
// The agent's identity. One record exists at all times.
Persona {
  name: String               // default "Claw"
  purpose: String            // what Claw is here to help with
  tone: String               // e.g. "calm, sharp, direct"
  values: [String]           // e.g. ["concise", "honest", "synthesis-focused"]
  expertiseAreas: [String]
  updatedAt: Date
}

// A single durable memory unit. Only written after user confirmation.
MemoryNote {
  id: UUID
  title: String
  summary: String            // synthesized insight, NOT a raw quote
  sourceLabel: String?       // e.g. article title, conversation date
  topics: [String]
  importanceScore: Float     // 0.0–1.0, used for search ranking
  isUserApproved: Bool
  createdAt: Date
  updatedAt: Date
}

// Per-topic interest and familiarity. Updated by feedback signals.
TopicProfile {
  id: UUID
  topicName: String
  interestScore: Float       // how much the user cares
  familiarityScore: Float    // how much the user already knows
  preferredDepth: String     // "surface" | "working" | "deep"
  lastUpdated: Date
}

// An imported local file Claw can read as context.
ImportedFile {
  id: UUID
  filename: String
  contentPreview: String     // first ~500 chars for context
  fullText: String           // full extracted text
  importedAt: Date
  lastAccessedAt: Date?
}

// A saved conversation session.
Conversation {
  id: UUID
  startedAt: Date
  messages: [Message]
  topicTags: [String]
}

Message {
  id: UUID
  role: String               // "user" | "assistant"
  content: String
  toolCallsMade: [String]    // names of tools called during this turn
  timestamp: Date
}
```

***

## Tools

These are the only actions Claw can take. Each is an app-defined `Tool` conforming to the Foundation Models tool protocol.

### 1. `searchMemory`
- **Input:** `query: String`
- **Behavior:** Fetches `MemoryNote` records from SwiftData. Search over `title`, `summary`, and `topics` fields. Sort by `importanceScore` descending, recency as tiebreaker. Return top 5.
- **Output:** Array of `{id, title, summary, topics, createdAt}`
- **Used when:** Claw needs prior context to answer well, or the user asks "do you remember..."

### 2. `saveMemoryNote`
- **Input:** `title: String, summary: String, topics: [String], importanceScore: Float, sourceLabel: String?`
- **Behavior:** Does NOT write immediately. Returns a draft payload to the model. The app renders a confirmation card in the chat UI. On user confirmation, the app writes to SwiftData with `isUserApproved = true`.
- **Output:** `{status: "pending_confirmation", draft: {...}}`
- **Used when:** Claw wants to preserve a synthesized takeaway.

### 3. `updateMemoryNote`
- **Input:** `id: UUID, patch: {title?, summary?, topics?, importanceScore?}`
- **Behavior:** Same confirmation pattern as `saveMemoryNote`. App shows the diff, user confirms, then SwiftData is updated.
- **Output:** `{status: "pending_confirmation", diff: {...}}`
- **Used when:** The user refines a memory by talking with Claw.

### 4. `readPersona`
- **Input:** none
- **Behavior:** Fetches the single `Persona` record from SwiftData and returns it as structured context.
- **Output:** Full `Persona` fields
- **Used when:** At session start (always injected), or when Claw needs to reason about its own purpose.

### 5. `proposePersonaUpdate`
- **Input:** `patch: {purpose?, tone?, values?, expertiseAreas?}`
- **Behavior:** Same confirmation pattern. Returns proposed diff for user approval before writing.
- **Output:** `{status: "pending_confirmation", proposed: {...}}`
- **Used when:** User says "be more concise", "focus on X", or the onboarding chat produces persona changes.

### 6. `listImportedFiles`
- **Input:** none
- **Behavior:** Returns metadata for all `ImportedFile` records.
- **Output:** Array of `{id, filename, importedAt, contentPreview}`
- **Used when:** Claw wants to know what context files are available.

### 7. `readImportedFile`
- **Input:** `id: UUID`
- **Behavior:** Fetches the full `fullText` from the matching `ImportedFile`. Truncate to fit context window if needed; return a truncation warning if so.
- **Output:** `{filename, fullText, truncated: Bool}`
- **Used when:** User says "look at this file" or Claw determines a file is relevant.

***

## System prompt

Injected into every `LanguageModelSession` at creation:

```
You are Claw, a private on-device AI agent. Your persona and purpose are defined in your memory files and loaded at the start of each session.

Rules:
- You have access to tools. Use them proactively when they would help you give a better answer.
- Always search memory before answering questions about the user's interests, goals, or past conversations.
- Never write to memory or update the persona without proposing the change first and getting user confirmation.
- Prefer short, precise responses. No filler. No hedging.
- If you cannot do something with your available tools, say so clearly and suggest what the user could do instead.
- All processing is on-device and private. Never reference external services.
```

***

## Session initialization

Every chat session should:
1. Call `readPersona()` and inject the result into session context.
2. Run `searchMemory("recent context active goals")` and inject top 3 results as background.
3. Keep last 10 conversation turns in context. Drop older turns silently.
4. Clear session context on app background per Foundation Models best practices.

***

## Onboarding flow

The first-run experience is a guided conversation, not a settings screen. It should feel like meeting Claw for the first time.

**Sequence:**
1. App shows a minimal welcome screen: "Meet Claw. Your private AI agent. Let's set it up — just talk."
2. Claw opens a chat and asks the first question: "What should I help you with? You can be specific — a project, a goal, a recurring problem you want a thinking partner for."
3. Claw follows up: "How would you like me to sound? Direct and sharp, warm and encouraging, or something else?"
4. Claw follows up: "What topics do you care most about right now? Name a few."
5. Claw summarizes what it learned and says: "Here's who I'll be for you. Does this feel right?" and shows a Persona preview card.
6. On confirmation, the app writes the first `Persona` record to SwiftData and starts the main chat.

**Implementation guidance:**
- Drive the onboarding with a Foundation Models session using a dedicated onboarding prompt, not the main system prompt.
- At the end, use guided generation to produce a structured `PersonaDraft` Swift object from the conversation, then write it to SwiftData.
- Onboarding should be re-accessible from Settings as "Reconfigure Claw."

***

## Chat UI

Single screen, minimal, text-first.

- Full-screen message list, reverse-chronological scroll.
- Pinned input bar at bottom: text field + send button + mic icon (mic is placeholder in v1).
- Floating "Import File" button, accessible but not prominent.
- When Claw calls a tool mid-response, show a subtle inline indicator: `Searching memory…` / `Reading file…` — this makes the agent feel like it is actually doing something.
- Confirmation cards: when a `saveMemoryNote`, `updateMemoryNote`, or `proposePersonaUpdate` is pending, render a distinct card in the message thread with a brief diff and two buttons: **Save** and **Discard**. Writing only happens on **Save** tap.
- Long-press on any assistant message: **Save to memory** shortcut — pre-fills a `saveMemoryNote` draft from the message content.

***

## File import flow

- User taps "Import File."
- `UIDocumentPickerViewController` opens, restricted to `.txt`, `.md`, `.pdf` (text extraction only for PDF), `.rtf`.
- On selection, app extracts text, creates an `ImportedFile` SwiftData record, and confirms in chat: "I've loaded [filename]. I can reference it when relevant."
- Claw does not auto-read every file. It reads a file when the user references it or when `listImportedFiles` reveals a relevant one.

***

## Implementation phases

### Phase 1 — Data layer and shell
**Goal:** App launches, SwiftData is wired, models exist, no AI yet.

- Set up SwiftData `ModelContainer` with all models: `Persona`, `MemoryNote`, `TopicProfile`, `ImportedFile`, `Conversation`, `Message`.
- Scaffold the main chat screen with static placeholder messages.
- Scaffold the onboarding screen with hardcoded text flow.
- Implement file import via `UIDocumentPickerViewController` and save to `ImportedFile`.
- Write a simple memory browser debug screen (list all `MemoryNote` records) — useful for testing later.

**Done when:** App launches without crashes, SwiftData stack is functional, a file can be imported and persisted.

***

### Phase 2 — Tools implementation
**Goal:** All seven tools are implemented as testable Swift functions, no Foundation Models yet.

- Implement each tool as a plain Swift function that takes typed inputs and returns typed outputs.
- `searchMemory`: implement basic text matching over `title`, `summary`, `topics` with score-based ranking.
- `saveMemoryNote` and `updateMemoryNote`: implement the "pending confirmation" state model — tools return a draft struct, UI observes it and renders a confirmation card.
- `readPersona`: simple SwiftData fetch of the single `Persona` record.
- `proposePersonaUpdate`: same confirmation pattern as memory write.
- `listImportedFiles` and `readImportedFile`: fetch from SwiftData, truncate text if over a reasonable limit (e.g. 4000 chars).
- Write unit tests for each tool using mock SwiftData contexts.

**Done when:** All tools can be called in isolation with correct outputs and confirmation state flows work end to end.

***

### Phase 3 — Foundation Models integration
**Goal:** Claw is live and chatting using on-device model with tool calling.

- Wrap each Phase 2 tool function in a Foundation Models `Tool` conformance.
- Create the `LanguageModelSession` with the system prompt and all seven tools.
- Wire the chat UI send action to the session: user message → session response → rendered in chat.
- Implement session initialization: `readPersona()` + `searchMemory("recent context")` injected at session start.
- Show inline tool-use indicators in the message list during generation.
- Handle `LanguageModelSession` availability check (device must support Apple Intelligence).
- Graceful error state if Foundation Models is unavailable: show a clear message explaining device/setup requirements.

**Done when:** User can have a real conversation with Claw, tool calls fire and return results, memory saves go through confirmation flow.

***

### Phase 4 — Onboarding flow
**Goal:** First-run experience produces a real `Persona` from conversation.

- Build the onboarding chat screen driven by a dedicated Foundation Models session.
- At the end of the conversation, use guided generation to produce a `PersonaDraft` Swift struct from the full conversation context.
- Show the Persona preview card and write to SwiftData on confirmation.
- Gate the main chat behind onboarding completion.
- Add "Reconfigure Claw" option in Settings that re-runs onboarding without wiping existing memory.

**Done when:** A new user can onboard, produce a real Persona, and land in a working chat with Claw already knowing their context.

***

### Phase 5 — Polish and coherence
**Goal:** The product feels like a complete, magical v1.

- Implement long-press "Save to memory" shortcut on assistant messages.
- Add a Memory browser screen: list all approved `MemoryNote` records, tap to expand, swipe to archive.
- Add a Persona view screen: current Persona fields, button to propose edits via chat.
- Implement session context management: keep last 10 turns, drop older turns gracefully.
- Add Markdown export of full memory to local Files.
- Audit every confirmation card for clarity: the user should immediately understand what Claw is proposing to save or change.
- Handle edge cases: empty memory, first-ever search, file too large to read.

**Done when:** App can be handed to a new user cold and they can explore it without instructions.

***

## Success criteria for v1

- User can onboard and produce a real, personalized Persona through conversation alone.
- Claw can find relevant prior memories when asked.
- Claw proposes memory saves that feel accurate and worth keeping.
- File import and reference works end to end.
- No writes to memory or persona happen without explicit user confirmation.
- Everything works fully offline on a supported device.
- The product creates at least one "wow, it actually remembered that" moment per session.

***

## What is explicitly out of scope for v1

- Web browsing or article analysis (future).
- Transcript import or audio analysis (future).
- Multi-agent or multiple Claw personas (future).
- iCloud sync or any network calls.
- Notes app integration (no public API).
- Voice input (mic is a placeholder).
- Proactive push notifications.
