# Manual Smoke Test — Mengo Desktop Phase 3b ("Mengo Flow — Mode C: Grab last N minutes")

Run before tagging `mengo-v2-phase-3b-flow-modec`. Spec:
`docs/superpowers/specs/2026-05-12-mengo-phase-3b-flow-modec-design.md`. Builds on Phase 3a's checklist (`mengo-phase-3a-flow.md`).

## Build & tests (scriptable)

- [ ] `swift build` — all targets compile.
- [ ] `swift test` — all suites pass (Phases 1/2 + the recording-source picker + Flow 3a + 3b).
- [ ] `./build-mengo.sh` — completes; `MengoDesktop.app` produced; `codesign --verify --deep --strict MengoDesktop.app` passes.

## App behaviour (run `open MengoDesktop.app`; needs a human + a working `claude` + screenpipe-MCP setup for the full walk-through)

### Opening the picker

- [ ] In the **Flow** idle pane, the **Grab last N minutes…** button (with a `⌃⌥G` caption) is now active (not "coming soon"). Click it → the Flow pane becomes the **timeline picker**.
- [ ] In the **menu-bar dropdown**, the Flow group's "Grab last 5 minutes… ⌃⌥G" is enabled → clicking it raises the main window onto the Flow tab and opens the picker.
- [ ] With the main window closed, pressing **⌃⌥G** raises the main window onto the Flow tab and opens the picker.

### The picker

- [ ] After a moment, the picker lists recent moments — `h:mm:ss am/pm` (mono) · **app name** · window title — newest first, with at most ≈one row per 15 s.
- [ ] The **Look back** picker (15 min / 30 min / 1 hour / 2 hours) re-queries; **Reload** re-queries.
- [ ] Click a moment → it highlights orange; a "Selected: 2:14 PM → now (Nm Ns)" caption appears; **Begin from here** enables.
- [ ] With a look-back range that has no screenpipe data → "No screenpipe data in that range. Try a longer look-back." and **Begin from here** stays disabled.
- [ ] **Cancel** (button, the menu's "Cancel timeline picker", or ⌃⌥R) → back to the Flow idle pane.

### Begin from here → retroactive recording

- [ ] Pick a moment from ~5–10 min ago → **Begin from here** → the picker closes; a floating HUD appears showing `● Recording 0:NN  Buffer: Nm Ns` and the hint "Narrate forward; you can also describe what happened earlier."; the Flow pane's recording text also shows a "Buffer: Nm Ns — the synthesizer will reconstruct that earlier window…" line.
- [ ] If preflight fails at this point (recorder paused / `claude` not on PATH / screenpipe MCP not configured), the standard preflight alert shows and the picker stays open.
- [ ] Continue the task while narrating, **and narrate something about the earlier (pre-pick) part** ("earlier I opened the staging dashboard and clicked Signups"). **Stop** (HUD button or ⌃⌥R) → synthesis runs.
- [ ] In the **Review**: the SKILL.md preview has a top note flagging some steps for verification; the step list shows the early (pre-narration) ones as "(inferred — verify)".
- [ ] **Save** → it's in the Library; invoke it via `claude` — confirm the demonstrated intent works.

### Recovery

- [ ] Start a Mode-C recording, then **quit the app** (⌘Q) mid-recording → relaunch → "An earlier recording was interrupted — synthesize it?" → **Synthesize it** → it synthesizes the whole grabbed window (a `mode: retroactive` recovery manifest, end = quit time).

### Regressions

- [ ] Mode A still works: **⌃⌥R** (or the Flow pane's "Start recording" / the menu's "Start recording…") begins a *proactive* recording (HUD shows no buffer line), Stop → synthesize → review → save.
- [ ] The Memory pane still works (record / pause / resume / Configure sources…); the recorder still starts on launch and stops on quit.
