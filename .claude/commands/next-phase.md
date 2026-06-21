---
description: Implement the next unbuilt phase of IMPLEMENTATION_PLAN.md and drive it through CI + TestFlight to merge, autonomously.
---

# /next-phase — autonomous phase loop

You are the orchestrator for this repo's phased build. Drive **one** phase from
code → green CI → successful TestFlight deploy → merge, with **no human
copy-paste**. Then start the next phase. Repeat until the plan is complete.

This project has **no Mac and no `xcodebuild` in this container** — GitHub
Actions is the only build/test substrate. Never try to build locally; observe
every result through the GitHub MCP tools.

Follow `CLAUDE.md` (Apple Foundation Models guidelines) for all Swift work.

## 0. Pick the phase

1. Read `IMPLEMENTATION_PLAN.md`. The **Status (live)** section lists each phase
   as `Phase N — built.` once done. The next phase is the lowest-numbered one
   **not** marked built (its detailed spec is under the `## Phase N — …` heading).
2. If every phase is built, stop and report completion — do not invent work.
3. If invoked with an argument (`/next-phase 7`), build that phase instead.

## 1. Implement

1. `git fetch origin main && git switch -c claude/phase-<N>-<slug> origin/main`
   (if the branch exists, switch to it and continue where it left off).
2. Implement the phase per its `## Phase N` spec and the `## D. Repository
   structure` conventions. Keep all FoundationModels code behind
   `#if canImport(FoundationModels)` per `CLAUDE.md`.
3. Commit with a descriptive message and `git push -u origin <branch>` (retry on
   network error with exponential backoff: 2s, 4s, 8s, 16s).

## 2. Open the PR and subscribe

1. `mcp__github__create_pull_request` (base `main`). Body: what the phase does +
   a checklist of the phase's acceptance criteria. **Do not** request a human
   reviewer.
2. `mcp__github__subscribe_pr_activity` for the PR — this wakes you on CI
   results, the deploy's `testflight/deploy` commit status, and review comments.
3. Start the heartbeat backbone (covers transitions webhooks miss). Run **once**
   per session, not per phase:
   `Monitor` (persistent) with `while true; do echo "tick $(date -u)"; sleep 600; done`.
   On each tick, re-check the active PR's CI + deploy state via MCP and advance.

## 3. Drive CI to green (the cheap gate)

`build.yml` runs the Debug/simulator build **and** the Release/device archive
proxy. The archive proxy is what catches the Release-only failures that used to
only surface in the deploy.

- Poll `mcp__github__pull_request_read` (status) / `actions_list` for the run.
- On failure: `mcp__github__get_job_logs` (`failed_only: true`), read the real
  error, fix on the branch, commit, push. Loop until **all** checks are green.
- Never dispatch the deploy while CI is red — the proxy exists precisely to avoid
  burning a TestFlight run on a cheaply-detectable failure.

## 4. Deploy to TestFlight (the merge gate)

Only after CI is green:

1. `mcp__github__actions_run_trigger` for `deploy.yml` with `ref` = the PR
   branch. This archives + signs + uploads to TestFlight, then publishes a
   `testflight/deploy` commit status (success/failure) on the branch head — which
   arrives as PR activity.
2. Watch the deploy run (`actions_get` / the commit status / `get_job_logs`).
3. Classify the outcome:
   - **Success** → go to §5.
   - **Code / archive failure** (compile, archive, packaging) → fix on the
     branch, push, return to §3.
   - **Account-level / signing failure** → the `beta` lane's `error do` handler
     prints a clear remediation block for unsigned/expired **agreements**; other
     signing/cert/Match/App-Store-Connect-auth errors are likewise **not
     code-fixable**. Detect these (agreement text, code-signing, provisioning,
     Match, ASC API key/auth) and **STOP**: call `AskUserQuestion` with the exact
     error and remediation. **Do not** retry-loop on these — retrying cannot fix
     an account problem.

## 5. Merge

Only once `testflight/deploy` is **success**:

1. Merge via `mcp__github__merge_pull_request` (squash). The TestFlight success
   is the merge gate — never merge before it.
2. (Optional) `enable_pr_auto_merge` instead, if `testflight/deploy` is a
   required check — then the merge fires automatically when CI + deploy are green.

## 6. Record progress and continue

1. On the merge commit / next session, update **both** status records so a
   restarted session resumes correctly:
   - `IMPLEMENTATION_PLAN.md` **Status (live)**: add `Phase N — built.` with a
     one-paragraph summary matching the existing entries' style.
   - `README.md` status table: set Phase N's State to `✅ built`.
   - Commit these to `main` (or fold into the phase PR before merge).
2. Begin the next phase: re-run this procedure from §0. The heartbeat tick will
   prompt you to continue if you are idle.

## Guardrails

- One phase = one PR. Don't batch phases.
- Stop and ask (`AskUserQuestion`) on: account/signing failures, ambiguous spec,
  or anything requiring a large refactor not described in the plan.
- The loop ends only when every phase is built, or the user tells you to stop
  (`unsubscribe_pr_activity` and halt).
