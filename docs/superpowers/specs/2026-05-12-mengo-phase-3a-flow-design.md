# Mengo Desktop — Phase 3a: Mengo Flow (proactive record → synthesize → review → save)

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Roadmap:** [`2026-05-12-mengo-desktop-playbook.md`](2026-05-12-mengo-desktop-playbook.md) — this is the first half of Phase 3 ("Mengo Flow — skill recording").
**V1 reference:** [`2026-05-12-screenpipeflow-design.md`](2026-05-12-screenpipeflow-design.md) — the standalone `ScreenpipeFlow` app this ports from. V1 source lives at `Sources/ScreenpipeFlow/`, kept intact as port reference.
**Branch:** new branch off `main` at `fe7e583` (the Memory recording-source picker work is already merged).

## Goal

From inside Mengo Desktop, the user demonstrates a task once — hit **Start recording** (the menu's Flow group or the `⌃⌥R` hotkey), narrate aloud what they're doing, hit **Stop** — and `claude -p` synthesizes a reusable Claude Code skill from the recording. The user reviews it inline (rename, edit the description and parameters, regenerate with feedback) and **Saves** it to `~/.claude/skills/<slug>/`. A floating, non-activating HUD shows recording state without stealing focus. The Library pane lists the flows Mengo has created.

This is **Phase 3a** of two: the proactive ("Mode A") loop. **Phase 3b** adds retroactive recording ("Mode C — Grab last N minutes": a Timeline thumbnail-strip picker over the current session's buffer, `⌃⌥G`). Splitting it keeps 3a a usable feature on its own and isolates Mode C's timeline UI (the riskiest piece).

screenpipe is already running and owned by Mengo Memory (Phase 2), so Flow never starts or installs the recorder — it only checks it's healthy and the mic isn't paused, and it bookkeeps a time range.

## Explicitly NOT in Phase 3a

| Deferred to | Item |
|---|---|
| Phase 3b | Mode C / "Grab last N minutes" / the Timeline thumbnail picker / `⌃⌥G` (stays disabled). |
| Phase 4 | Codex CLI as a synthesis runtime (the runtime selector lives in Settings); Cowork plugin output writer; Free/Pro gating (≤3 flows etc.). |
| Phase 5 | Studio's visual node-graph editor; in-place step editing in Review (V1 keeps `flow.json` steps read-only — the lever is "Regenerate with feedback…"); replay verification. |
| Out of scope | Recording trimming/splicing; multi-user/sync; skill marketplace. |

## Architecture

Same model as V1: **Swift orchestrates, `claude` does the semantics.** Mengo Flow contains no LLM logic, no parsing of recordings, no variable detection, no timeline segmentation. It marks a time range, writes a manifest JSON, spawns `claude -p` with a bootstrap prompt + the manifest path, waits, renders the result. All the hard work (querying screenpipe via the `mcp__screenpipe__*` tools, interpreting frames/OCR/audio, deriving intent + parameters + steps, writing `SKILL.md` / `flow.json` / `frames/*.png`) happens inside the `claude` subprocess. The bootstrap prompt at `Resources/synthesis-prompt.md` is a load-bearing, git-versioned artifact.

```
 ┌─ Mengo Desktop (this app) ───────────────────────────────────────────┐
 │  Memory (Phase 2): owns the screenpipe process — already running     │
 │  Flow  (this phase):                                                 │
 │    FlowController ── start/stop, preflight ── RecordingHUD (NSPanel) │
 │         │ on stop                                                    │
 │         ├─ ManifestWriter ─► ~/Library/Application Support/          │
 │         │                     MengoDesktop/flows/manifests/<uuid>.json│
 │         └─ SynthesisRunner ─► spawns:                                 │
 │                claude -p --dangerously-skip-permissions               │
 │                          --add-dir ~/.claude/skills                   │
 │                          [synthesis-prompt.md + manifest path]        │
 │                env: SCREENPIPE_API_KEY=<recorder token>               │
 └──────────────────────────────────────────────────────────────────────┘
        │ HTTP /health, /audio/* (preflight only)        │ spawns
        ▼                                                ▼
   screenpipe (127.0.0.1:3030, owned by Memory)     claude -p subprocess
        ▲                                                │ queries via
        └──────────── mcp__screenpipe__* ◄───────────────┘ screenpipe MCP
                                                         │ writes
                                                         ▼
                            ~/.claude/skills/<slug>/{SKILL.md, flow.json, frames/*.png}
```

### State boundaries

| Location | Owned by | Contents |
|---|---|---|
| `~/Library/Application Support/MengoDesktop/flows/` | Flow | `manifests/<uuid>.json` (pending synthesis inputs), `library.json` (the created-flows index), `recovery/<uuid>.json` (interrupted-recording dumps). |
| `~/.screenpipe/` | screenpipe | Recording data. Flow reads via HTTP (preflight) / the MCP (inside `claude`); never writes. |
| `~/.claude/skills/<slug>/` | Claude Code / the user | Synthesis output (`SKILL.md`, `flow.json`, `frames/*.png`). Flow lists it (Library) and renders it (Review); written by the `claude` subprocess. |
| `~/Library/Logs/MengoDesktop/` | Mengo Desktop | `recorder.log` (Phase 2) + `flow.log` (Flow app log) + `synthesis-<id>.log` (per-synthesis subprocess stdout/stderr). |

## The Flow pane state machine

The "Flow" sidebar entry shows a state machine (the `ComingSoonPane` for `.flow` is replaced):

| State | UI |
|---|---|
| `idle` | Hero: "Record a task once → get a reusable skill." Big brand-orange **Start recording** button (`⌃⌥R` hint). A 3-step how-it-works blurb. A greyed "Grab last N minutes… — coming soon" (3b). |
| `recording(FlowSession)` | "● Recording 0:42 — narrate your task; use the floating panel to stop." (The HUD is the real control; the pane just reassures.) |
| `synthesizing(manifestURL)` | A spinner: "Building your skill… ~30 s–2 min. Keep working — you'll get a notification when it's ready." |
| `reviewing(skillURL)` | The `SkillReviewView` (below). |
| `error(String)` | "Synthesis failed — `<reason>`." Buttons: **View log** (opens `synthesis-<id>.log`), **Retry** (re-runs `claude -p` on the same manifest), **Discard** (deletes the half-written skill dir + manifest, → `idle`). |

`error` is also used for preflight failures (with a fix message instead of [Retry]/[View log] — see Error handling).

### `SkillReviewView` (the `reviewing` state)

Renders the just-synthesized skill. Layout (consistent with the Memory pane / the recording-sources sheet — dark palette, orange accents):

- **Header** — editable **name** + **description** (editing the name re-slugs the directory on Save).
- **SKILL.md preview** — the generated markdown, rendered (SwiftUI `Text` with `AttributedString(markdown:)` / a lightweight Markdown view).
- **Parameters** — editable list: rename, edit default, remove, **+ Add parameter**. Parameters the synthesizer auto-detected are visually flagged ("auto-detected — confirm or remove").
- **Steps** — read-only summary list from `flow.json` (`1. Open the staging dashboard (inferred — verify)` …). Editing steps is Phase 5; the lever here is Regenerate.
- **Footer** — **[Regenerate with feedback…]** (a small sheet: a text field for feedback; on submit re-runs `claude -p` with the same manifest + `regenerationContext`, replacing the skill dir, → `synthesizing`), **[Discard]** (deletes the skill dir + manifest, → `idle`), **[Save]** (finalizes; collision handling below; updates the library index; → `idle`; a "Saved to ~/.claude/skills/<slug>/" notification).

### Library pane

The "Library" sidebar entry (replaces its `ComingSoonPane`) — a list of flows Mengo has created, from `library.json`. Per row: **name** · **created date** · **[Open in Finder]** (the skill dir) · **[Re-open in Review]** (→ Flow pane, `reviewing` state, that skill) · **[Delete]** (confirms; deletes the skill dir; removes the index entry). An entry whose skill dir no longer exists shows greyed with "(missing — removed outside Mengo)" and only a [Remove from list] action. Empty state: "No flows yet — record one from the Flow tab."

### Recording HUD

A floating `NSPanel` with `styleMask = [.nonactivatingPanel, .hudWindow]` (and `level = .floating`, `collectionBehavior` so it shows on all Spaces) — never becomes key, never steals focus from whatever the user is demonstrating. Content: `●  Recording   0:23   [Stop]` and a hint line ("Narrate as you work."). Draggable; remembers its last position in `UserDefaults`. Shown by `FlowController` on Start, removed on Stop. (Mengo Desktop is a Dock app that stays running with its main window closed, so the HUD works regardless of the main window's state.)

### Menu bar (the "Flow" group)

`MenuBarContent.swift` un-disables the Flow group: **Start recording…** `⌃⌥R` / **Stop recording** (the same item, toggled by `FlowController.state`). **Grab last 5 minutes… `⌃⌥G`** stays disabled (3b). When `synthesizing`, the group shows a disabled "Synthesizing…" item. The menu-bar glyph (`MenuBarLabel`) is unchanged — it still reflects the *recorder* (Memory) status, not Flow.

## Components

**Ported from `Sources/ScreenpipeFlow/` into `Sources/MengoDesktop/`** — renaming for the new namespace; `~/Library/Application Support/ScreenpipeFlow/` → `…/MengoDesktop/flows/`; logs → `~/Library/Logs/MengoDesktop/`; the V1 separate-`Window`-scenes structure is dropped (Review/Library are inline panes; Timeline is 3b):

| New file | From V1 | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/FlowSession.swift` | `RecordingSession.swift` | Value type: `mode: .proactive` (the only value in 3a; `.retroactive` lands in 3b), `activeRecordingStart: Date`, `endTime: Date?`, `manifestId`. |
| `Sources/MengoDesktop/FlowController.swift` | `RecordingController.swift` + parts of `AppState.swift` | `@Observable @MainActor`. Owns `flowState: FlowState`. `start()` (preflight → spawn HUD → set `activeRecordingStart`), `stop()` (set `endTime` → ManifestWriter → SynthesisRunner), `regenerate(feedback:)`, `retrySynthesis()`, `discard()`, `save(name:description:parameters:)`. Deps injectable for tests (process spawner, screenpipe client, clock, library) — same pattern as `RecorderController`. Holds a weak ref to `RecorderController` for the "resume mic" preflight fix and to read the recorder's auth token. `AppDelegate.sharedFlowController` bridge (mirrors `sharedRecorder`). |
| `Sources/MengoDesktop/ManifestWriter.swift` | `ManifestWriter.swift` | Serializes a finished `FlowSession` (+ `userHints`, `outputDir = ~/.claude/skills`, optional `regenerationContext`) → `…/flows/manifests/<uuid>.json`, schema as in the V1 spec (`manifestVersion: 1`). Pure, easily tested. |
| `Sources/MengoDesktop/SynthesisRunner.swift` | `SynthesisRunner.swift` | Spawns `claude -p --dangerously-skip-permissions --add-dir ~/.claude/skills` with `[contents of synthesis-prompt.md, with $MANIFEST_PATH set]`; sets `SCREENPIPE_API_KEY=<recorder token>` and a sane `PATH` in the env; tees stdout/stderr to `~/Library/Logs/MengoDesktop/synthesis-<id>.log`; parses the final stdout line as `{"status":"ok",…}` / `{"status":"error","message":…}`; reports the result. Process-spawn injectable for tests; the final-line parser is a pure function (tested directly). |
| `Sources/MengoDesktop/ScreenpipeFlowClient.swift` | subset of `ScreenpipeClient.swift` | 3a needs only the preflight bits: `/health` reachable + `audio_status`. (Reuses the existing `APIClient`/`ScreenpipeHealth` from Phase 2 where possible rather than duplicating — likely this collapses into a couple of helper calls on the existing client; if so, no new file.) The frame-thumbnail query is 3b's Timeline. |
| `Sources/MengoDesktop/HotkeyManager.swift` | `HotkeyManager.swift` | Carbon `RegisterEventHotKey`: `⌃⌥R` → `FlowController.toggleRecording()`. (`⌃⌥G` registration is 3b.) Register on launch, unregister on terminate. |
| `Sources/MengoDesktop/Slug.swift` | `Slug.swift` | kebab-case slug derivation + collision suffixing (`name → "staging-signups-report"`, `… → …-2`). Pure. |

**New files:**

| File | Responsibility |
|---|---|
| `Sources/MengoDesktop/FlowState.swift` | The `enum FlowState` above + (if not on `FlowController`) the recovery-manifest discovery. |
| `Sources/MengoDesktop/FlowLibrary.swift` | The created-flows index. `…/flows/library.json` — `[{ slug, name, path, createdAt, sourceManifestId }]`. `add`, `remove`, `all` (each entry tagged `.ok` / `.missing` by checking the dir exists). Injectable file location for tests. |
| `Sources/MengoDesktop/FlowPane.swift` | The SwiftUI pane rendering `FlowController.flowState` (idle / recording / synthesizing / error). |
| `Sources/MengoDesktop/SkillReviewView.swift` | The `reviewing`-state UI (above). Loads `SKILL.md` + `flow.json` from the skill dir, parses frontmatter (name/description) + parameters + steps for editing/display. |
| `Sources/MengoDesktop/LibraryPane.swift` | The Library list (above). |
| `Sources/MengoDesktop/RecordingHUD.swift` | The floating `NSPanel` controller + its SwiftUI content. |

(`Logger.swift` from V1 — fold into the existing `Log`; don't add a second logger.)

**Wiring changes:**
- `Sources/MengoDesktop/MenuBarContent.swift` — un-disable the Flow group; "Start recording…"/"Stop recording" toggled by `FlowController.state`; keep `⌃⌥G` disabled; add a disabled "Synthesizing…" item while synthesizing.
- `Sources/MengoDesktop/MainWindowView.swift` — `case .flow: FlowPane(flow:)`, `case .library: LibraryPane(flow:)`; remove those two from the `default: ComingSoonPane` fallthrough.
- `Sources/MengoDesktop/MengoDesktopApp.swift` — `@State private var flow = FlowController(recorder:)` (constructed with the `RecorderController`); pass `flow` into `MainWindowView` and `MenuBarContent`; `applicationDidFinishLaunching` also: register the hotkey, request `UNUserNotificationCenter` authorization, and run `FlowController.checkForRecovery()` (offer "Finish synthesizing your interrupted recording?" if a recovery manifest exists); `applicationWillTerminate` also dumps a recovery manifest if `flowState` is `.recording` and unregisters the hotkey.
- `Sources/MengoDesktop/Theme.swift` — no new tokens expected.
- `Resources/synthesis-prompt.md` — already present; carried as-is (path-parameterized; no `ScreenpipeFlow`-specific strings to change — confirm during implementation).
- `build-mengo.sh` — already copies `Resources/` into the bundle; confirm `synthesis-prompt.md` ends up in the `.app` (the V1 `ScreenpipeFlow` target listed it as a `.copy` resource; the `MengoDesktop` target's `Package.swift` resources list needs the same entry).
- `Info.plist` — no new entries for 3a (`claude`/screenpipe are subprocesses; the mic/screen usage strings already exist; local notifications use `UNUserNotificationCenter` runtime auth, no plist key needed).

## Data formats

Carried verbatim from the V1 spec — `manifestVersion: 1` (mode `"proactive"` only in 3a; `timeRange.start == activeRecordingStart`; `regenerationContext` populated on Regenerate); `SKILL.md` frontmatter + Intent/Parameters/Steps; `flow.json` `schemaVersion: 1` with `parameters[]` (`autoDetected` flag) and `steps[]` (`type`, `inferred`, `intent`, `evidence`, `executionHints`). The synthesis prompt's `{"status":"ok","outputDir":…,"slug":…}` / `{"status":"error","message":…}` final-line contract is unchanged.

## Error handling

Principle (from V1): *fail visibly, fail recoverably, never silently ship a broken skill.*

**Preflight (before recording starts — block Start, explain):**
| Condition | Detection | UX |
|---|---|---|
| screenpipe not healthy / not responding | `RecorderController.status` ≠ recording, or `/health` fails | "The recorder isn't running right now — check the Memory tab." Start disabled. |
| Mic capture paused | `RecorderController` audio is paused | "Your microphone is paused — Flow needs it. Resume?" One-click `RecorderController.resumeAudio()`. |
| `claude` CLI not in PATH | spawn `claude --version`; not found / non-zero | "Claude Code CLI not found. Install it from claude.ai/code, then retry." |
| screenpipe MCP not configured for `claude` | parse `claude mcp list`; `screenpipe` absent | Shows the exact fix: `claude mcp add screenpipe -s user -- npx -y screenpipe-mcp`, with a [Copy] button. |

**Synthesis MCP auth (the one integration subtlety):** `SynthesisRunner` sets `SCREENPIPE_API_KEY=<the recorder's per-launch token>` in the `claude -p` subprocess env so the `screenpipe-mcp` child (spawned by `claude`) inherits it and can authenticate against Mengo's recorder. If the user's globally-configured `screenpipe` MCP entry sets its own conflicting `env` (which would shadow the inherited var), that's an edge case for the implementation plan to resolve — likely by Mengo refreshing/normalizing the `screenpipe` MCP config on launch, or by documenting the requirement in the preflight message. (Captured as an open question below.)

**In-recording:** app quits or crashes mid-recording → in-memory `FlowSession` is lost, but `applicationWillTerminate` best-effort dumps `…/flows/recovery/<uuid>.json` (with `endTime = quit time`); next launch, `FlowController.checkForRecovery()` finds it → "You stopped recording a flow at <time> by quitting. Finish synthesizing it?" → synthesizes the partial (works without Mode C). User declines → the recovery manifest is moved aside / deleted.

**Synthesis (post-stop):**
| Condition | Detection | UX |
|---|---|---|
| Recording too short (<10 s) | duration check before spawning | Notification "Recording too short to synthesize." → `idle`. No spawn. |
| No narration | `{"status":"error","message":"no narration"}` | "No narration captured — try again and describe what you're doing." → `idle`. |
| Subprocess failed (non-zero exit / unparsable stdout) | exit code + final-line parse | `error` state: "Synthesis failed." + [View log] (`synthesis-<id>.log`) + [Retry] (re-spawn on the same manifest) + [Discard]. Manifest preserved. |
| Timeout (>5 min wall clock) | wall clock | Prompt: "Synthesis is taking longer than expected. Keep waiting / cancel?" Cancel → kill the subprocess → `error` with [Retry]. |

**Save:** slug already exists in `~/.claude/skills/` → prompt "Replace / Save as `<slug>-2` / Cancel". Disk write failure → standard error dialog with the failing path; stays in `reviewing`.

## Testing

**Swift unit tests** (most port from `Tests/ScreenpipeFlowTests/`):
- `FlowState` / `FlowController` transitions: `idle → recording → synthesizing → reviewing → idle (Save)`; `… → idle (Discard)`; `reviewing → synthesizing (Regenerate)`; `synthesizing → error (subprocess fail) → synthesizing (Retry)`; preflight failures → `error` without entering `recording`. (Stubbed process spawner, screenpipe client, clock, library.)
- `ManifestWriter`: schema-valid JSON for proactive + regeneration cases; round-trips through a decoder.
- `Slug`: derivation from name / intent; kebab-casing; collision suffixing.
- `FlowLibrary`: add / remove / `all`; persists across instances; an entry whose dir is gone is tagged `.missing`.
- `SynthesisRunner`: the final-status-line parser — `{"status":"ok",…}` parses, `{"status":"error","message":…}` parses, trailing text after the JSON is tolerated, garbage → a clear failure. (Pure function; the `Process` spawn itself isn't unit-tested.)
- `HotkeyManager`: register + unregister cleanly (no real key events).
- `FlowController` preflight with a stubbed screenpipe client (healthy / unreachable / mic-paused) and a stubbed `claude --version` / `claude mcp list`.
- The existing `RecorderControllerTests` etc. keep passing (no behavior change to Memory).

**No SwiftUI view tests** (none in this repo) — `FlowPane` / `SkillReviewView` / `LibraryPane` / the HUD are covered by the manual checklist.

**New manual smoke checklist** `docs/manual-smoke-tests/mengo-phase-3a-flow.md`:
- Record a real task (open a webpage, copy a value, paste into Slack), narrating; Stop; watch the spinner; get the notification; Review shows a sensible SKILL.md + parameters + steps; Save; the flow appears in the Library pane; invoke the skill via Claude Code (`claude` → use the skill) and confirm it does the intent.
- A deliberate parameter callout ("treat my email — `me@example.com` — as a variable `user_email`") → `user_email` appears in the Review parameters list (and as `{{user_email}}` in SKILL.md).
- "Regenerate with feedback…" with a note ("rename to `staging-report`; make `slack_channel` default `#growth`") → the regenerated skill reflects it.
- Discard → the skill dir and manifest are gone.
- Preflight: with the recorder paused / `claude` not on PATH / the screenpipe MCP not configured → the right block message (and the [Copy] of the `claude mcp add …` command works).
- `⌃⌥R` toggles recording from outside the app; the HUD floats over other apps, never steals focus, is draggable, remembers position.
- Quit mid-recording → next launch offers "Finish synthesizing your interrupted recording?"; accept → it synthesizes the partial.
- Recording <10 s → "too short", no synthesis.

**Build + `swift test` green; rebuild the `.app` (`./build-mengo.sh`), relaunch, walk the checklist.** (Synthesis quality itself — "did `claude` produce a *good* skill" — isn't unit-testable; the V1 spec sketches an `evals/` harness, but that's out of scope for 3a; the manual checklist is the honest bar.)

## Out of scope (Phase 3a)

Mode C / "Grab last N minutes" / the Timeline picker / `⌃⌥G` (Phase 3b). Codex runtime; Cowork output writer; Free/Pro gating (Phase 4). Studio editor; in-place step editing in Review; replay verification (Phase 5). The synthesis-eval harness. Recording trimming/splicing; multi-user/sync.

## Open questions for the implementation plan

- **screenpipe MCP auth for `claude -p`**: confirm `screenpipe-mcp` reads `SCREENPIPE_API_KEY` from its env (it should — it talks to the same authenticated HTTP API). Decide whether Mengo should also *normalize* the user's `screenpipe` MCP config on launch (so a stale `env` in their existing config doesn't shadow the inherited token), or just rely on the inherited env + a clear preflight message. Leaning: rely on inherited env for 3a; revisit if it bites.
- **`ScreenpipeFlowClient` vs reusing `APIClient`**: preflight only needs `/health` + audio status, which the Phase 2 `APIClient` already exposes (`health()` → `ScreenpipeHealth.audioStatus`) — so likely *no new client file*, just a couple of preflight helpers on `FlowController` using the existing client. Confirm during the plan; if true, drop `ScreenpipeFlowClient.swift` from the file list.
- **Markdown rendering for the SKILL.md preview**: `AttributedString(markdown:)` is enough for headings/lists/inline code; if it falls short (tables, code fences), a tiny custom renderer or `Down`-style lib — but no dependency unless needed. Decide in the plan.
- **`claude -p` flags**: V1 used `--dangerously-skip-permissions --add-dir <skills-dir>`; confirm the current `claude` CLI still takes these and whether `--print`/`-p` plus `--output-format` needs pinning so the final-line parse is stable. (If `claude -p` interleaves tool-use chatter on stdout, the parser must scan for the *last* JSON line — V1 already does this; carry it.)
- **Hotkey conflicts**: `⌃⌥R` is unregistered if already taken by another app (`RegisterEventHotKey` fails) — surface a quiet note in the Flow pane ("⌃⌥R is in use by another app — use the menu, or rebind in Settings later") rather than failing hard. Confirm the V1 behavior and carry it.
