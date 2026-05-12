# Mengo Desktop — V2 Phase-by-Phase Playbook

**Date:** 2026-05-12
**Status:** Draft — awaiting user review

## Purpose

This document is the **roadmap**, not a design spec. It lays out the five
phases for building Mengo Desktop V2 in order. Each phase gets its own full
brainstorm → spec → plan → implementation cycle when it begins. Use this
playbook to decide what to do *next*, not as a guide to how to *build* any
individual phase.

V1 design context lives at
[`2026-05-12-screenpipeflow-design.md`](2026-05-12-screenpipeflow-design.md) —
specifically the "Roadmap → V2: Mengo Desktop" section.

---

## Cross-cutting decisions (apply to every phase)

These are locked at the playbook level so each phase doesn't re-litigate them.

### Recording lifecycle: tied to app lifecycle

**Decision:** Recording starts when the user opens Mengo Desktop and stops
when they quit it. The menu bar icon only appears while the app is running.

| | V1 | V2 (this decision) |
|---|---|---|
| Recorder runs | 24/7 in the background after install | Only while Mengo Desktop is open |
| Menu bar icon | Always visible | Only while Mengo Desktop is open |
| Battery cost | Constant low-level capture overhead | Zero when not in use |
| Privacy posture | "Anything I do is being captured by default" | "I have to deliberately open the app to be captured" |

**Trade-off worth surfacing:** Mode C ("grab the last N minutes") becomes
**bounded by the current app session**, not by a 24/7 buffer. If you open
Mengo at 9am and try Mode C at 9:02, you only have ~2 minutes of buffer to
scrub. This is intentional — the privacy upside outweighs the loss of
retrospective depth — but Mode C's pitch shifts from *"reach into anywhere in
your past"* to *"reach back into this session."*

### Single unified menu bar dropdown

**Decision:** Mengo Desktop has **one** menu bar item, not three (Memory +
Flow + Studio). The dropdown is sectioned by product. Quick draft of the
layout:

```
Mengo
● Recording  (10m 23s)

Memory
  Pause audio
  Pause screen
  Open data folder

Flow
  Start recording…   ⌃⌥R
  Grab last 5 minutes…  ⌃⌥G

Library  →
Studio  →            (Pro)
Settings…
Quit
```

Library and Studio open windows in the main app. Memory's pause/resume
controls stay in the menu for convenience (they're the operations the user
might want without bringing the main window forward).

### Tech stack

Swift 6 / SwiftUI throughout, matching V1's `ScreenpipeMenu` and
`ScreenpipeFlow` baseline. SwiftPM project. Apple Silicon, macOS 15+. Ad-hoc
codesign for V2; notarization is a post-V2 question.

### Codebase location

**Open question — needs resolution before Phase 1 starts:**

- (a) **New repo `~/screenpipe-mengo-desktop/`** (or rename the current
  `~/screenpipe/` repo to `~/mengo-desktop/`). Greenfield, copy useful
  pieces from V1.
- (b) **Continue in the current `~/screenpipe/` repo**, evolving V1 in place.
  Less churn, but the repo name no longer matches.
- (c) **New repo at `~/Desktop/Mengo/`** to match the existing Claude
  project metadata reference, but the Bash sandbox here can't write to
  `~/Desktop/` so we'd lose this Claude session's ability to work there.

My recommendation: **(b)** — continue in `~/screenpipe/`, with V1 code intact
as historical reference, and add new V2 code under `Sources/MengoDesktop/`.
Rename the *binary* (`MengoDesktop.app`) without renaming the repo. Defer
the repo-rename to V2 cleanup.

### Data directory

V1 wrote to `~/.screenpipe/` (owned by the screenpipe binary). For V2:

**Open question:** rename to `~/.mengo/` or keep `~/.screenpipe/`?

- Rename pros: matches the brand, clearer to the user
- Rename cons: screenpipe binary writes there by default; renaming means
  patching screenpipe's config or symlinking
- Keep pros: zero migration, no risk

My recommendation: **keep `~/.screenpipe/` for V2**, document it as a known
"naming inheritance from upstream" in settings ("Open data folder" still
opens `~/.screenpipe/`), and revisit when we have leverage to rename it.

---

## The phases (in order)

### Phase 1 — The shell

**Goal:** A launchable Mengo Desktop app with a window, navigation between
Memory/Flow/Studio panes, and a single menu bar dropdown that appears when
the app is open. No real recording, no synthesis, no licensing. The panes
contain placeholder content ("Memory — coming in Phase 2").

**In scope:**
- Swift app target `MengoDesktop` with `@main` entry, `WindowGroup` scene,
  and a single `MenuBarExtra` scene.
- Main window UI shell: left sidebar with Memory / Flow / Library / Studio /
  Settings; right pane swaps content based on selection.
- Menu bar dropdown with the layout sketched above. Pause/resume buttons
  exist but call into no-op stubs.
- App icon, color tokens, basic typography — define the design system once
  so later phases don't each pick their own colors.
- `applicationWillTerminate` lifecycle plumbing (so Phase 2 can hook
  recorder shutdown).
- Single bundled `Info.plist` with `LSUIElement=false` (we want a Dock
  icon now that this is a full app, not a menubar-only utility — confirm
  with user during Phase 1 brainstorm).
- New `Resources/MengoDesktopInfo.plist`, `build-mengo.sh`.

**NOT in scope:**
- Any recording (Phase 2)
- Any synthesis or skill creation (Phase 3)
- License gating — every feature is unlocked in Phase 1 (Phase 4)
- Studio's node-graph editor (Phase 5)

**Dependencies:** none. This is greenfield.

**Key decisions to make in Phase 1's brainstorm:**
- Dock icon (windowed app) vs menu-bar-only — answer determines `LSUIElement`.
- Window layout: sidebar nav vs tab bar vs document-style multiple windows.
- App icon source — design or AI-generated for now.

**Estimated build size:** ~15–20 TDD tasks. Largely SwiftUI scaffolding.

---

### Phase 2 — Mengo Memory (Screenpipe recording)

**Goal:** When the user opens Mengo Desktop, the screenpipe recorder spins
up; when they quit, it shuts down cleanly. Status, pause/resume audio,
pause/resume screen, and "Open data folder" all work from the unified menu
bar dropdown. The Memory pane in the main window shows recording status,
recent activity timeline, and a search box (search is Phase 2.5 if it
grows too big).

**In scope:**
- Port `BinaryManager.swift`, `RecorderProcess.swift`, `APIClient.swift`
  from V1's `ScreenpipeMenu` into the new app, namespacing as needed.
- Wire screenpipe lifecycle to the app's launch/terminate signals (start
  on `applicationDidFinishLaunching`, stop on `applicationWillTerminate`).
- Hook pause/resume into the existing screenpipe HTTP API (already works
  in V1).
- Status indicator in the menu bar label that mirrors V1's "● Recording"
  / "Audio paused" / "Error" semantics.
- TCC permission prompts (Screen Recording, Microphone) on first launch.
- Crash recovery: if screenpipe segfaults, surface "Error — click to
  restart" in both the menu and the Memory pane.

**NOT in scope:**
- Full vector-index search of memory ("what was that staging URL?") —
  Pro feature, post-phase
- Memory exports / saving search results
- Privacy schedules (pause schedule, app blocklists) — Phase 4 settings

**Dependencies:** Phase 1 shell complete (need the menu bar and the
`applicationWillTerminate` hook to plug into).

**Key decisions to make in Phase 2's brainstorm:**
- Where the screenpipe binary lives: bundled (V1 pattern) or downloaded on
  first launch? V1 used both — bundling is simpler.
- Whether to keep V1's auto-update of the screenpipe binary version.
- Handling the `~/.screenpipe/` vs `~/.mengo/` data-dir question (locked
  to "keep" above, but confirm).

**Estimated build size:** ~10–15 tasks. Most code already exists in V1 —
this is mostly integration and lifecycle wiring.

---

### Phase 3 — Mengo Flow (skill recording)

**Goal:** From inside Mengo Desktop, the user can hit "Start recording" in
the menu (or `⌃⌥R`), narrate a task, hit Stop, and get a synthesized skill
saved to `~/.claude/skills/<slug>/`. Mode C ("Grab last 5 minutes…") works
against the **current app session's recording buffer**. Review and Library
windows are the in-app surface (not separate windows like V1 — they're
panes in the main window).

**In scope:**
- Port `AppState.swift`, `RecordingSession.swift`, `RecordingController.swift`,
  `ScreenpipeClient.swift`, `ManifestWriter.swift`, `SynthesisRunner.swift`,
  `Slug.swift`, `HotkeyManager.swift`, `Logger.swift` from V1's
  `ScreenpipeFlow`.
- Floating recording HUD (V1 `RecordingHUD.swift`) — keep as floating panel.
- Move Timeline, Review, Library from separate `Window` scenes to inline
  panes in the main window's content area.
- Carry forward the permission fix already shipped in V1 (`--dangerously-
  skip-permissions --add-dir <skills-dir>` flags).
- Synthesis still shells out to `claude -p` for V2 launch. The Codex
  toggle (Settings → runtime selector) is Phase 4 territory; for Phase 3
  we hard-code Claude.

**NOT in scope:**
- Codex CLI as a runtime option (Phase 4 — needs settings infrastructure)
- Cowork plugin output writer (Phase 4 — needs settings + accounts)
- Studio's node-graph editor (Phase 5)
- Free/Pro skill-count gating (Phase 4)

**Dependencies:** Phase 2 complete (need a running screenpipe to query).
The lifecycle change means Phase 3's `ScreenpipeClient` doesn't need to
worry about "is screenpipe running?" preflight — if Mengo is open, it's
running.

**Key decisions to make in Phase 3's brainstorm:**
- Inline panes vs windows for Review / Library. V1 used separate windows;
  inline is more app-like.
- Should the Recording HUD float over other apps (V1) or stay inside the
  Mengo window? Floating is more useful for actual demos.

**Estimated build size:** ~15–20 tasks. Most code exists; the win is the
inline-pane refactor and the unified menu integration.

---

### Phase 4 — Account & licensing

**Goal:** User can sign in to their Mengo account, paste/manage their
license key, and see Free vs Pro status reflected in the UI. Pro-only
features (unlimited flows, MCP integrations, Codex runtime, Studio,
replay) are gated correctly. An "Upgrade to Pro" button opens the web
checkout (Stripe via the website's flow) and deep-links back.

**In scope:**
- Sign-in flow: OAuth or magic-link via mengo.ai (which mechanism does
  the website use? — open question for Phase 4 brainstorm).
- License validation: app calls `mengo.ai/api/license/validate` periodically
  (e.g. on launch + once per day) and caches the result locally.
- Free vs Pro gating:
  - **Free:** ≤3 saved flows, limited recordings (limit TBD with user),
    local-only memory, no Studio editor, no Codex export, no MCP
    integration helpers.
  - **Pro:** all of the above unlocked.
- "Upgrade to Pro" button → opens `mengo.ai/upgrade?return=mengo://...`,
  Stripe checkout completes, web redirects to `mengo://license-installed`,
  the app installs the new license token.
- Settings panel for the runtime selector (Claude vs Codex) — wired into
  Phase 3's synthesis call site.
- Settings: capture, storage, hotkeys, MCP integration helpers,
  privacy schedules.

**NOT in scope:**
- Cloud sync of flows / memory (post-V2)
- Team / multi-seat licensing (post-V2)
- Self-serve license refunds, plan changes (handled on the website)

**Dependencies:** Phase 3 complete (need flow creation to gate against
the 3-flow Free limit). Phase 1 settings UI shell.

**Key decisions to make in Phase 4's brainstorm:**
- Auth mechanism — depends on what the website (built by separate Claude
  session) exposes. Cross-reference the `Mengo.ai` repo when accessible.
- Where the license token is stored (Keychain is the right answer,
  confirm).
- What "limited recordings" means in Free tier — minutes per day? Total
  recordings? Recording length cap? Needs product decision.
- Offline behavior — if `mengo.ai/api/license/validate` is unreachable,
  do we trust the cached status, fail-open to Free, fail-closed (lock
  the app)?
- Deep-link URL scheme registration (`mengo://`) and Info.plist setup.

**Estimated build size:** ~20–25 tasks. Most net-new code in V2. URL
handling, keychain, secure HTTP, gating logic across the app.

---

### Phase 5 — Mengo Studio (visual flow editor + replay)

**Goal:** Open a saved flow from the Library, see its `flow.json` rendered
as a node graph. Edit a step's intent, command, or screenshot inline. Add
branches/conditions. Reorder steps. Save → regenerates SKILL.md. Run a
flow via Replay, watching status per step ("step 3: in-progress / passed
/ failed") in real time.

**In scope:**
- Node-graph editor view. Renders `flow.json`'s `steps` array. Each step
  is a node with editable fields.
- Drag-to-reorder, drag-to-connect for branches.
- "Edit-by-natural-language" sidebar: type "change step 3 to use Firefox,"
  click Apply, claude regenerates that single step.
- Replay panel: choose a flow, click Run, watch the agent execute it.
  Live status streaming from the runtime back into the UI.
- Replay verification: compare detected end-state to demonstrated. Surface
  mismatches inline.

**NOT in scope:**
- Multi-user / shared editing (post-V2)
- Cowork-style publishing of edited flows back to a team library
  (post-V2 or its own phase)
- Recording trimming / re-recording portions of a flow inline (likely V3
  territory)

**Dependencies:** Phase 3 (Flow needs to exist before there's anything to
edit). Phase 4 (Studio is gated to Pro).

**Key decisions to make in Phase 5's brainstorm:**
- Native SwiftUI for the node graph vs embedding a WebView with a JS
  library (React Flow, Rete.js). Native is consistent with the rest of
  the app but Swift has no mature node-graph library; WebView gives
  battle-tested editors out of the box but introduces a tech-stack seam.
- Streaming replay status from the agent — does `claude -p` support
  streaming, or do we have to poll?
- How replay verification's "matches expected end-state" actually works
  in practice (likely an agent-judged comparison rather than pixel diff).

**Estimated build size:** ~30–40 tasks. The biggest phase by far — it's
the only one with no V1 ancestor to port. Plan to budget at least 2x any
prior phase.

---

## What this playbook does NOT cover

- Detailed UI mockups for any phase (those come in each phase's brainstorm).
- The mengo.ai landing-page integration specifics — cross-reference the
  separate Claude session that owns the website when those questions land.
- V3 (Windows + proactive skill recommender) — see the V1 spec's Roadmap
  section.

## Suggested working pattern

For each phase:

1. **Brainstorm** the phase using `superpowers:brainstorming`. Resolve the
   "Key decisions" listed in the phase's section, plus any net-new questions
   that arise.
2. **Write a spec** at `docs/superpowers/specs/YYYY-MM-DD-mengo-phase-N-<name>-design.md`.
3. **Write a plan** at `docs/superpowers/plans/YYYY-MM-DD-mengo-phase-N-<name>.md`.
4. **Execute** task-by-task (subagent-driven or inline).
5. **Tag a phase release** when the manual smoke checklist for the phase
   passes (e.g. `mengo-v2-phase-1-shell`).

Phases land independently — at the end of Phase 2 the app records but
doesn't synthesize; at the end of Phase 3 it records and synthesizes but
doesn't gate; etc. Each is shippable as a TestFlight-style internal build.

## Open questions to resolve BEFORE Phase 1 starts

1. **Codebase location** — pick (a), (b), or (c) above. Default: (b).
2. **Dock icon vs menu-bar-only** — `LSUIElement` decision.
3. **App icon source** for V2 — designed, AI-generated, or a placeholder
   for now.
4. **`~/.screenpipe/` vs `~/.mengo/` data dir** — locked to "keep" above
   unless objection.
5. **Whether to copy V1 code over wholesale at Phase 1 start** (to have it
   available for Phases 2-3) or pull each file just-in-time. Default:
   wholesale copy at Phase 1, then refactor as we go.
