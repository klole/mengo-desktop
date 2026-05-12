# ScreenpipeFlow — Demonstration-to-Skill Recorder Design

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan

## Goal

A macOS app, separate from ScreenpipeMenu, that lets the user demonstrate a task once and produces a reusable Claude Code skill from it. The user's spoken narration during the demonstration is the source of truth for intent; screenpipe's always-on recording (owned by ScreenpipeMenu) is the data source. Synthesis runs via the Claude Code CLI as a subprocess — no Anthropic API tokens are spent.

This is the second of two tools in a planned pair:

- **Tool 1: ScreenpipeMenu** *(exists)* — always-on macOS menu bar app that runs the screenpipe recorder.
- **Tool 2: ScreenpipeFlow** *(this design)* — on-demand demonstration capture, producing reusable agent skills.

## Decisions (locked)

| | |
|---|---|
| Target workflow scope | Any task (coding / CLI, browser, native macOS apps, mixed). |
| Source of truth | User's spoken narration. Actions are grounding evidence. |
| Trigger modes | **Proactive** (record fresh) + **Retroactive** (grab last N minutes from screenpipe's buffer, then continue forward). |
| Output target | Claude Code skill (`~/.claude/skills/<slug>/`) only for V1. Codex adapter deferred. |
| Synthesis runtime | `claude -p` subprocess. No Anthropic API calls. Uses the user's existing Claude Code subscription. |
| App packaging | Separate Swift app from ScreenpipeMenu. Both apps read screenpipe's data; neither calls the other's process. |
| Platform | macOS 15 (Sequoia) +, Apple Silicon (matching Tool 1). |

## In scope for V1

- Proactive trigger mode: user-triggered start/stop for fresh demonstrations.
- Retroactive trigger mode: user picks a past start time from screenpipe's buffer, then continues recording forward.
- Narration-driven parameter detection: phrases like "that's a variable" or "call this `user_email`" become parameters. Auto-detection of obvious parameters (emails, paths) is also done by the synthesizer, marked for user confirmation.
- Per-recording manifest written to disk, consumed by `claude -p` for synthesis.
- Three artifacts produced per skill: `SKILL.md`, `flow.json`, `frames/*.png` — all in `~/.claude/skills/<slug>/`.
- Post-synthesis Review window: rename, edit description, edit parameters, regenerate with feedback.
- Library window: list of created flows with re-open / delete actions.

## Explicitly NOT in V1

| Deferred to | Item |
|---|---|
| V2 (native cross-platform app) | N8N-style visual flow editor; direct in-place step editing. |
| V2 | Windows support. |
| Post-V1 | Codex CLI output adapter. |
| Post-V1 | Multi-user / sharing / sync between machines. |
| Post-V1 | Replay verification (skill self-checks success). |
| Out of scope | Skill marketplace / discovery. |
| Out of scope | Recording trimming, splicing, or editing. V1 = re-record or regenerate. |

## Architecture

```
┌────────────────────────────────────────────────────────────────┐
│  Tool 1: ScreenpipeMenu (existing, unchanged)                  │
│  └─ owns screenpipe process lifecycle                          │
└────────────────────────────────────────────────────────────────┘
                              │ starts / stops
                              ▼
┌────────────────────────────────────────────────────────────────┐
│  screenpipe (always-on background recorder)                    │
│  - SQLite at ~/.screenpipe/                                    │
│  - HTTP API at 127.0.0.1:3030                                  │
│  - MCP server (`screenpipe-mcp`)                               │
└────────────────────────────────────────────────────────────────┘
        ▲                                       ▲
        │ HTTP queries for timeline previews    │ queries via MCP
        │                                       │ for full synthesis
┌───────┴──────────────────────┐    ┌───────────┴────────────────┐
│  Tool 2: ScreenpipeFlow      │    │  claude CLI subprocess     │
│  (NEW — this design)         │───▶│  spawned with `claude -p`  │
│  - Menubar item              │    │  + path to manifest        │
│  - Recording HUD             │    │  + synthesis prompt        │
│  - Timeline window (mode C)  │    │                            │
│  - Review window             │    │  Headless. Uses user's     │
│  - Library window            │    │  existing CC subscription. │
└──────────────────────────────┘    └─────────────┬──────────────┘
                                                  │ writes
                                                  ▼
                            ┌─────────────────────────────────────┐
                            │  ~/.claude/skills/<slug>/           │
                            │  ├─ SKILL.md      (intent + params) │
                            │  ├─ flow.json     (structured       │
                            │  │                 timeline; V2     │
                            │  │                 editor seed)     │
                            │  └─ frames/*.png  (key screenshots) │
                            └─────────────────────────────────────┘
```

### Key architectural properties

- **Tool 1 and Tool 2 don't know about each other.** Both talk to screenpipe; neither calls into the other's process. ScreenpipeFlow degrades gracefully if ScreenpipeMenu isn't installed ("screenpipe not running — please install ScreenpipeMenu first").
- **Synthesis is offloaded entirely.** ScreenpipeFlow contains no LLM logic, no parsing of recordings, no prompt templates beyond a single bootstrap. It writes a manifest to disk, spawns `claude -p`, waits. Claude Code does everything else — querying screenpipe via MCP, interpreting frames and audio, producing markdown and JSON. The hard problem lives in a prompt, not in Swift code.
- **Process model:** ScreenpipeFlow is one Swift app process. `claude` runs as a transient subprocess per synthesis call (typically 30s–2min). screenpipe runs as its own long-lived process (owned by Tool 1).

### State boundaries

| Location | Owned by | Contents |
|---|---|---|
| `~/Library/Application Support/ScreenpipeFlow/` | Tool 2 | Pending/recovery manifests, library index, settings. |
| `~/.screenpipe/` | screenpipe | Recording data. Tool 2 reads via HTTP/MCP; never writes. |
| `~/.claude/skills/<slug>/` | Claude Code / user | Synthesis output. Tool 2 lists and reviews; written by `claude` subprocess. |
| `~/Library/Logs/ScreenpipeFlow/` | Tool 2 | App log + per-synthesis subprocess logs. |

## Swift components

ScreenpipeFlow is a single Swift app process. About ten files, organized by lifecycle, integration, and UI.

### Lifecycle & state

- **`ScreenpipeFlowApp.swift`** — `@main` entry. Declares a `MenuBarExtra` scene plus three `Window` scenes (Timeline, Review, Library) that only appear when triggered. Wires `applicationWillTerminate` to flush in-flight manifest to recovery dir.
- **`AppState.swift`** — `@Observable` class. Holds:
  - `sessionState: SessionState` enum: `.idle`, `.browsingTimeline`, `.recording(RecordingSession)`, `.synthesizing(URL)`, `.reviewing(URL)`, `.error(String)`
  - `library: [FlowEntry]` — index of created flows (name, path, createdAt)
  - `screenpipeStatus: ScreenpipeStatus` — polled health
  - User preferences (hotkey bindings, save-path overrides)
- **`RecordingSession.swift`** — value type: `mode: .proactive | .retroactive`, `bufferRangeStart: Date?` (mode C only), `activeRecordingStart: Date`, `endTime: Date?`.

### Recording control

- **`RecordingController.swift`** — start/stop logic. Verifies preconditions (screenpipe healthy, audio active, claude CLI present, screenpipe MCP configured). Triggers `ManifestWriter` + `SynthesisRunner` on stop.
- **`HotkeyManager.swift`** — global hotkey registration (default `⌃⌥R` for start/stop, `⌃⌥G` for grab-last). Uses `Carbon.HIToolbox` `RegisterEventHotKey`.

### screenpipe integration

- **`ScreenpipeClient.swift`** — thin HTTP wrapper over `http://127.0.0.1:3030`. Used by Tool 2 for:
  - Health check (`/health`)
  - Audio status — verify mic capture isn't paused before starting
  - Frame thumbnails for the Timeline window (mode C) — `/search?content_type=frame&...`

  Deep queries (full transcript, accessibility tree) happen inside the `claude` subprocess via the screenpipe MCP, not from Tool 2.

### Synthesis pipeline

- **`ManifestWriter.swift`** — serializes a completed `RecordingSession` to JSON at `~/Library/Application Support/ScreenpipeFlow/manifests/<uuid>.json`.
- **`SynthesisRunner.swift`** — spawns `claude -p` with a bootstrap prompt + the manifest path, captures stdout/stderr to a log file, parses the final JSON status line. Posts `.synthesisComplete(URL)` or `.synthesisFailed(String)` to AppState.

### UI surfaces

- **`MenuBarView.swift`** — menubar dropdown. Items: "Start recording" / "Stop recording" (toggles), "Grab last 5 minutes…" (opens TimelineWindow), "Open library", "Settings", "Quit".
- **`RecordingHUD.swift`** — small floating window during active recording. Non-activating panel (`NSPanel.styleMask = [.nonactivatingPanel, .hudWindow]`). Shows elapsed time, optional buffer indicator (mode C), Stop button, narration hint. Draggable, remembers position.
- **`TimelineWindow.swift`** — mode C UI. Horizontal strip of frame thumbnails over the last N hours (queried from screenpipe), with a draggable start-point handle. User picks a start, clicks "Begin from here" → enters recording state.
- **`ReviewWindow.swift`** — post-synthesis. Renders the generated SKILL.md (markdown preview), editable parameter list, read-only step summary. Buttons: Save, Regenerate with feedback…, Discard.
- **`LibraryWindow.swift`** — list of saved flows. Per row: name, created date, Open in Finder, Re-open review, Delete.

### Utility

- **`Logger.swift`** — file-based logger to `~/Library/Logs/ScreenpipeFlow/app.log`; separate stream for synthesis subprocess logs.

**Design property: no semantic logic in Swift.** Tool 2 doesn't parse audio, doesn't interpret frames, doesn't detect variables, doesn't segment the timeline. All semantic work lives in the `claude -p` prompt. Swift orchestrates: marks time ranges, writes manifests, spawns subprocesses, renders results. This is what keeps the codebase tractable.

The bootstrap prompt at `Resources/synthesis-prompt.md` is therefore a **load-bearing artifact** — versioned in git, iterated on when synthesis quality is poor.

## Data formats

### Manifest schema

JSON file at `~/Library/Application Support/ScreenpipeFlow/manifests/<uuid>.json`. Written by `ManifestWriter`, consumed by `claude -p`.

```json
{
  "manifestVersion": 1,
  "manifestId": "01HZK8...",
  "createdAt": "2026-05-12T14:32:17Z",
  "mode": "proactive",
  "timeRange": {
    "start": "2026-05-12T14:31:45Z",
    "end":   "2026-05-12T14:32:17Z"
  },
  "activeRecordingStart": "2026-05-12T14:31:45Z",
  "userHints": {
    "name": null,
    "description": null,
    "notes": null
  },
  "outputDir": "/Users/kyle/.claude/skills",
  "regenerationContext": null
}
```

**Mode-specific fields:**
- *Proactive (A):* `timeRange.start == activeRecordingStart` — user hit record and started narrating immediately.
- *Retroactive (C):* `timeRange.start` is the buffer-range-start (selected from the timeline); `activeRecordingStart` is when the user started narrating forward. The interval `[timeRange.start, activeRecordingStart)` is the un-narrated portion that the synthesizer must reconstruct from observation.

**Regeneration:** when the user clicks "Regenerate with feedback…" in Review:

```json
"regenerationContext": {
  "previousSkillPath": "/Users/kyle/.claude/skills/check-staging-signups",
  "userFeedback": "Rename to 'staging-signups-report'. Make slack_channel optional, default '#growth'."
}
```

### Bootstrap synthesis prompt

A bundled resource at `Resources/synthesis-prompt.md`, loaded by `SynthesisRunner`, passed to `claude -p`. Iterated independently of the Swift code.

```
You are synthesizing a Claude Code skill from a recorded user demonstration.

The user demonstrated a task on their Mac, narrating aloud what they were
doing so it could be captured as a reusable skill. Convert the recording
into a Claude Code skill directory.

INPUTS:
  - Manifest at: $MANIFEST_PATH
  - The screenpipe MCP tools (mcp__screenpipe__*) for querying the recording

PROCESS:
  1. Read $MANIFEST_PATH. Note timeRange and activeRecordingStart.
  2. Use screenpipe MCP to fetch over the time range:
     - Audio transcript (user narration) — primary source of truth for INTENT
     - OCR text + accessibility events — grounding evidence
     - 5-15 key screenshots at semantic boundaries (app switch, click,
       scroll burst)
  3. NARRATION IS PRIMARY. If user says "log into the staging dashboard"
     and opens dashboard.example.com, encode the intent as "log into the
     staging dashboard" — not "navigate to a specific URL". The URL is
     just evidence.
  4. PARAMETER DETECTION: scan narration for variable callouts. Phrases
     like "that's a variable", "call this X", "this part is different
     each time", "my email is X — treat as a parameter" all become
     entries in the parameters list. Replace concrete values with
     {{param_name}} in SKILL.md and flow.json. Also auto-detect obvious
     parameters (account names, emails, file paths) even without explicit
     callout, but mark them "autoDetected": true so the user can confirm
     or reject in Review.
  5. MODE "retroactive": [timeRange.start, activeRecordingStart) is
     pre-narration. Reconstruct those steps from screen + accessibility
     alone. Tag each such flow.json step with "inferred": true. Add a
     note at the top of SKILL.md flagging those steps for verification.
     If the user narrates retrospectively ("earlier I was opening the
     dashboard"), align that narration with the corresponding past frames.
  6. SLUG: derive from userHints.name, else from intent. kebab-case.

OUTPUT to <outputDir>/<slug>/:
  - SKILL.md       (format below)
  - flow.json      (schema below)
  - frames/*.png   (key screenshots; reference by relative path)

On success, print exactly one final line to stdout:
  {"status":"ok","outputDir":"<absolute path>","slug":"<slug>"}
On failure:
  {"status":"error","message":"<one-line reason>"}
```

The prompt is short by design — long prompts crowd out the model's reasoning budget.

### SKILL.md format

The user-facing artifact. Claude Code reads this when the skill is invoked. Example:

```markdown
---
name: staging-signups-report
description: Pull today's signup count from the staging dashboard and post
  a one-line summary to Slack. Use when checking overnight activity.
---

# Staging Signups Report

## Intent

Open the staging admin dashboard, navigate to the Signups page, read
today's count, and post a summary to a Slack channel.

## Parameters

- `slack_channel` *(default: `#growth`)* — Slack channel to post the summary to.

## Steps

1. **Open the staging dashboard.** *(inferred from observation — verify)*
   Navigate to the staging admin dashboard. The user typically uses
   Chrome with an SSO-authenticated session. See `frames/01.png`.

2. **Open the Signups page.** Click "Signups" in the left sidebar.
   See `frames/02.png`.

3. **Read today's count.** Find the "Today" card; extract the number.
   See `frames/03.png`.

4. **Post to Slack.** Send to `{{slack_channel}}`:
   `staging signups today: <count>`
```

### flow.json schema

Structured representation; not consumed at V1 invoke-time, but the seed data for V2's visual editor.

```json
{
  "schemaVersion": 1,
  "name": "staging-signups-report",
  "intent": "Pull today's signup count and post to Slack.",
  "createdAt": "2026-05-12T14:35:02Z",
  "sourceManifest": "01HZK8...",
  "parameters": [
    {
      "name": "slack_channel",
      "description": "Slack channel to post the summary to.",
      "exampleValue": "#growth",
      "default": "#growth",
      "autoDetected": false
    }
  ],
  "steps": [
    {
      "id": 1,
      "type": "browser",
      "inferred": true,
      "intent": "Open the staging dashboard",
      "evidence": {
        "audioQuote": null,
        "frameRef": "frames/01.png",
        "ocrContext": "Staging Admin · Dashboard",
        "appName": "Google Chrome",
        "timestamp": "2026-05-12T14:31:45Z"
      },
      "executionHints": {
        "tool": "claude-in-chrome",
        "command": "navigate to dashboard.staging.example.com"
      }
    }
  ]
}
```

**Step `type` values:** `"terminal"`, `"browser"`, `"native"`, `"observation"` (a non-action moment, e.g., "wait for page to load"). The synthesizer picks based on the frontmost app and accessibility context.

**`executionHints.tool` values:** `"Bash"`, `"claude-in-chrome"`, `"computer-use"`, or `null` (the agent at invoke-time decides).

## UX walkthroughs

### Mode A — Proactive recording

The user knows in advance they want to capture a skill.

1. **Trigger.** Menubar → "Start recording" or global hotkey `⌃⌥R`.
2. **Preflight.** RecordingController verifies screenpipe is healthy and microphone capture is active.
   - *screenpipe not running:* error dialog with "Open ScreenpipeMenu" button.
   - *Audio paused:* "Your microphone is paused. Resume?" One-click resume via Tool 1's HTTP API.
3. **Recording.** `RecordingHUD` appears top-right:
   ```
   ●  Recording          0:23
   "Narrate as you work."     [Stop]
   ```
   Non-activating; never steals focus. Draggable; remembers position.
4. **User performs the task** while narrating. screenpipe captures everything as normal — Tool 2 is just bookkeeping a time range.
5. **Stop.** Stop button, or `⌃⌥R` again. HUD disappears.
6. **Synthesis.** State transitions to `.synthesizing`. Menubar icon shows a subtle spinner. User can keep working. `ManifestWriter` saves the manifest; `SynthesisRunner` spawns `claude -p` and waits (typically 30s–2min).
7. **Notification.** "Skill 'staging-signups-report' ready for review." Click → `ReviewWindow`.

### Mode C — Retroactive recording

The user is mid-flow and realizes a moment is worth saving.

1. **Trigger.** Menubar → "Grab last N minutes…" or `⌃⌥G`.
2. **TimelineWindow opens.** Strip of frame thumbnails over the last ~30 minutes (lazy-loaded; scroll further back to extend). Under each thumbnail: frontmost app name, timestamp. A right-edge marker labels "Now"; a draggable handle on the left selects the start point.

   ```
   ┌─────────────────────────────────────────────────────────────┐
   │  Pick where the task started:                              │
   │                                                            │
   │  [thumb][thumb][thumb][thumb][thumb][thumb][thumb][thumb]  │
   │  Chrome Chrome Slack  Slack  Chrome Chrome Chrome  Now     │
   │  14:25  14:27  14:29  14:30  14:31  14:33  14:34          │
   │       ▲                                                    │
   │       └─ Start                                             │
   │                                                            │
   │  Selected window: 14:25:00 → now (9m 42s)                  │
   │                              [Cancel]  [Begin from here]   │
   └─────────────────────────────────────────────────────────────┘
   ```
3. **User picks a start point** by dragging or clicking. Optional: scrub audio preview at the selected moment.
4. **Begin from here.** Window closes; state goes to `.recording` with `mode=retroactive`, `bufferRangeStart` set to the selected timestamp, `activeRecordingStart = now`.
5. **HUD appears** with a buffer indicator:
   ```
   ●  Recording forward     0:08    (Buffer: 9m 42s)
   "Narrate what you're doing now, and you can also
    describe what happened earlier."        [Stop]
   ```
6. **User continues the task while narrating.** Critically, the user can describe the un-narrated past *retroactively*: "Earlier I opened the staging dashboard, clicked Signups, and saw the count is 847." The synthesizer aligns retrospective narration with corresponding past frames.
7. **Stop → synthesis** — same path as mode A, except inferred steps get `"inferred": true` in `flow.json` and a "verify before relying on this" note in `SKILL.md`.

### Shared path — Review

Identical for both modes once synthesis completes.

`ReviewWindow` is a single resizable window:

```
┌──────────────────────────────────────────────────────────────────┐
│  staging-signups-report                                         │
│  ─────────────────────────────                                  │
│  Pull today's signup count and post to Slack.                   │
│                                                                  │
│  ┌── SKILL.md preview ───┐ ┌── Parameters ──────────────────┐   │
│  │                       │ │ slack_channel   default=#growth│   │
│  │  (rendered markdown)  │ │   [Edit] [Remove]              │   │
│  │                       │ │                                │   │
│  │                       │ │ [+ Add parameter]              │   │
│  │                       │ │                                │   │
│  │                       │ ├── Steps ───────────────────────┤   │
│  │                       │ │ 1. Open the staging dashboard  │   │
│  │                       │ │    (inferred)                  │   │
│  │                       │ │ 2. Navigate to Signups page    │   │
│  │                       │ │ 3. Read today's count          │   │
│  │                       │ │ 4. Post to Slack               │   │
│  └───────────────────────┘ └────────────────────────────────┘   │
│                                                                  │
│  [Regenerate with feedback…]  [Discard]  [Save]                 │
└──────────────────────────────────────────────────────────────────┘
```

- **Name + description** editable inline. Editing the name re-slugs the directory.
- **Parameters list** is editable: rename, remove, add, edit defaults. Auto-detected parameters are visually flagged for confirm/reject.
- **Steps list** is read-only in V1. Editing steps is V2's job (the visual editor). If a step is wrong in V1, the user clicks "Regenerate with feedback…" and writes a note: "Step 2 isn't right — I click 'Users' not 'Signups'."
- **Regenerate** re-runs `claude -p` with the same manifest plus `regenerationContext` populated. The previous skill directory is replaced.
- **Save** finalizes. LibraryWindow refreshes. Notification: "Skill saved to ~/.claude/skills/<slug>/."
- **Discard** deletes the skill directory and the manifest.

## Error handling

Principle: *fail visibly, fail recoverably, never silently ship a broken skill.*

### Preflight (before recording starts) — block and explain

| Error | Detection | UX |
|---|---|---|
| screenpipe not running | `/health` check fails | Dialog: "screenpipe is not running. Open ScreenpipeMenu to start the recorder." Disables Start. |
| Audio capture paused | `/health` returns audio_status != "running" | Prompt: "Your microphone is paused. Resume?" One-click resume via Tool 1's pause/resume HTTP endpoint. |
| Claude Code CLI not in PATH | Spawn `claude --version`; non-zero exit or not found | Dialog: "Claude Code CLI not found. Install from claude.ai/code, then retry." |
| screenpipe MCP not configured | `claude mcp list` parsed; absent | Dialog with the exact fix command: `claude mcp add screenpipe -s user -- npx -y screenpipe-mcp` |

### In-recording — fail soft, recover from screenpipe data

- *Tool 2 crashes or user quits mid-recording.* In-memory session state is lost; screenpipe data on disk is intact. **Recovery: user re-opens Tool 2, uses mode C to scrub back to the crash point.** Mode C *is* the recovery path — no special recovery code beyond best-effort recovery manifest dump.
- *`applicationWillTerminate` during a recording.* Best-effort: dump current session manifest to `~/Library/Application Support/ScreenpipeFlow/recovery/`. On next launch, AppState detects it and offers "Recover unfinished recording?"

### Synthesis (post-stop) — show the error, offer retry

| Error | Detection | UX |
|---|---|---|
| Recording too short (<10s) | Duration check | Notification: "Recording too short to synthesize." No synthesis attempted. |
| No narration detected | Synthesizer returns `{"status":"error","message":"no narration"}` | Notification: "No narration captured — try again and describe what you're doing." |
| `claude` subprocess fails (non-zero exit, malformed stdout) | Exit code + stdout parse | Notification with "View log" → opens `~/Library/Logs/ScreenpipeFlow/synthesis-<id>.log`. Manifest preserved; user can retry. |
| Synthesis timeout (>5 min) | Wall clock | Prompt: "Synthesis is taking longer than expected. Continue waiting / cancel?" |

### Save — collision handling

- *Slug collision in `~/.claude/skills/`.* Prompt: "A skill named `staging-signups-report` already exists. Replace / save with suffix `-2` / Cancel?"
- *Disk write fails.* Standard error dialog with the failing path.

## Testing strategy

Three automated layers, scaled by what's tractable, plus a manual checklist.

### 1. Swift unit tests (XCTest)

- State machine transitions in `AppState` (idle → recording → synthesizing → reviewing).
- `ManifestWriter` produces valid JSON matching the manifest schema for all mode/regen combinations.
- Slug derivation from name / intent: `"Staging Signups Report" → "staging-signups-report"`; collision suffixing.
- `HotkeyManager` registers and tears down cleanly.

### 2. Integration tests (ScreenpipeClient)

- Health check parsing against captured fixture responses from a real screenpipe.
- Timeline thumbnail query handles empty windows (no data in range).
- Audio status detection across `running` / `paused` / `error` states.

### 3. Synthesis eval (LLM behavior)

You can't unit-test the synthesizer's semantic output. But you can regression-eval it:

- `evals/` directory with 5–10 fixtures, each containing:
  - A manifest JSON.
  - A captured screenpipe data snapshot for that time range (frames + transcript + accessibility events, exported via screenpipe's API into a tarball).
  - An `expected.md` listing properties of a good output: "SKILL.md must mention the Slack channel as a parameter," "flow.json must have a step of type=browser with intent containing 'dashboard'."
- A `run-evals` script that for each fixture runs `claude -p` against the manifest + an injected MCP serving the snapshot, captures output, grades against `expected.md` via a separate `claude -p` judge call.
- Track scores over time as `synthesis-prompt.md` evolves. A change that drops eval scores is a regression.

### 4. Manual end-to-end checklist

The only honest answer for V1 quality. A documented checklist the developer runs before each release. Items like:

- Record yourself opening a webpage, copying a value, pasting into Slack. Save the skill. Invoke via Claude Code. Confirm Claude can execute the intent.
- Use mode C to retroactively capture a task from 10 min ago. Verify inferred steps are flagged.
- Record a task with a deliberate variable callout ("this email is my variable user_email"). Confirm `user_email` appears as a parameter.

The automated layers catch regressions in plumbing; only the manual layer catches "the synthesizer got worse."

## V2-friendliness — seeds we plant in V1

| V1 seed | What V2 picks up |
|---|---|
| `flow.json` structured schema | The N8N-style visual editor renders `steps` as nodes, `executionHints` as action specifics, `evidence.frameRef` as inline thumbnails. |
| Separate-app architecture | V2's cross-platform app can replace ScreenpipeFlow entirely without disturbing Tool 1 (which keeps running as the macOS data source; Windows gets its own equivalent). |
| `claude -p` synthesizer (no API tokens) | V2 uses the same recipe — `claude -p` and/or `codex -p` shelled out from the native app. The synthesis prompt iterates with V1. |
| Library window + flow index | V2's "your flows" view is this, scaled up with the visual editor as the per-flow inspector. |
| `regenerationContext` field | V2 supports edit-by-natural-language ("change step 3 to use Firefox") via the same mechanism, just from inside the visual editor. |
| Parameter system (`{{var_name}}` substitution) | V2 surfaces parameters as input fields at invoke-time, with type hints. |

## Open questions for the implementation plan

- Whether `MenuBarExtra` plus separate `Window` scenes is the right SwiftUI pattern, or whether a more imperative `NSApplicationDelegate`-driven setup gives better control over the HUD's non-activating behavior. Spike during plan phase.
- How `claude -p` handles MCP tool access in headless mode. Verify that `mcp__screenpipe__*` tools are available to a `claude -p` invocation when the user has run `claude mcp add screenpipe -s user`. If not, the synthesis prompt may need to invoke screenpipe via its HTTP API instead of MCP.
- Whether to use `screenpipe-mcp` directly or `screenpipe`'s HTTP API for thumbnails in the Timeline window. HTTP is simpler; MCP gives richer queries. Start with HTTP.
- App distribution: ad-hoc signed `.app` bundle following Tool 1's pattern, or notarized via the Apple Developer Program. Likely ad-hoc for V1 (matches Tool 1).
