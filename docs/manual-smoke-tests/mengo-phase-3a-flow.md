# Manual Smoke Test — Mengo Desktop Phase 3a ("Mengo Flow")

Run before tagging `mengo-v2-phase-3a-flow`. Spec:
`docs/superpowers/specs/2026-05-12-mengo-phase-3a-flow-design.md`.

## Build & tests (scriptable)

- [ ] `swift build` — all targets compile.
- [ ] `swift test` — all suites pass (Phases 1/2 + the recording-source picker + Flow's new tests).
- [ ] `./build-mengo.sh` — completes; prints `screenpipe vX.Y.Z (arch) embedded`; produces `MengoDesktop.app` + `.zip`.
- [ ] `MengoDesktop.app/Contents/Resources/synthesis-prompt.md` exists; `codesign --verify --deep --strict MengoDesktop.app` passes.

## Prereqs for the full Flow walk-through (needs a human + a real Claude Code setup)

- Claude Code CLI installed and on PATH (`claude --version` works).
- The screenpipe MCP configured for Claude Code: `claude mcp add screenpipe -s user -- npx -y screenpipe-mcp` (if not, Flow's preflight will tell you the exact command).
- Mengo Memory's recorder running (open the app — it starts automatically) with the mic not paused.

## App behaviour (run `open MengoDesktop.app`)

### Panes & menu

- [ ] The sidebar's **Flow** and **Library** rows now show real panes (not "coming soon").
- [ ] The **Flow** pane (idle) shows the "Mengo Flow" hero, a brand-orange **Start recording** button with a `⌃⌥R` caption, a 3-step "how it works" blurb, and a greyed "Grab last N minutes… — coming soon".
- [ ] The **Library** pane shows "No flows yet — record one from the Flow tab." (until you make one).
- [ ] The menu-bar dropdown's **Flow** group has an enabled "Start recording… ⌃⌥R"; "Grab last 5 minutes… ⌃⌥G" is disabled.

### Record → synthesize → review → save (Mode A)

- [ ] **Start** (Flow pane button, menu, or `⌃⌥R`): a small **floating HUD** appears top-right — `● Recording 0:NN [Stop]` + "Narrate as you work." It's draggable, remembers its position next time, **never steals focus** from other apps, and shows on all Spaces.
- [ ] Demonstrate a real task — e.g. open a webpage, copy a value, paste it into Slack — narrating aloud what you're doing and why.
- [ ] **Stop** (HUD's Stop button or `⌃⌥R`): the HUD disappears; the Flow pane shows a spinner + "Building your skill…". You can keep working.
- [ ] When it finishes, a notification "Skill ‘…’ ready for review" arrives, and the Flow pane is now the **Review** view: a sensible SKILL.md preview, a parameters list, a read-only step list, and an editable name/description.
- [ ] **Save** → the Flow pane returns to idle; the new flow appears in the **Library** pane.
- [ ] In a terminal: `claude`, then use the new skill — confirm Claude can execute the demonstrated intent.

### Variations

- [ ] **Parameter callout:** record a task narrating "treat my email — me@example.com — as a variable `user_email`". In Review, `user_email` is in the parameters list; `{{user_email}}` appears in the SKILL.md preview.
- [ ] **Regenerate with feedback…** with a note ("rename to staging-report; default `slack_channel` to #growth") → the regenerated skill reflects it.
- [ ] **Discard** (in Review) → the skill directory and its manifest are gone; Flow pane back to idle; Library doesn't list it.
- [ ] **Recording < 10 s** → a "Recording too short to synthesize." notification; no Review.

### Preflight failures (block Start, explain)

- [ ] With Mengo Memory's mic paused → "Your microphone is paused…" (resume from the Memory tab).
- [ ] With `claude` not on PATH → "Claude Code CLI not found…".
- [ ] With the screenpipe MCP not configured for `claude` → an alert with `claude mcp add screenpipe -s user -- npx -y screenpipe-mcp` and a working **Copy command** button.

### Recovery

- [ ] Start a recording, then **Quit** the app (⌘Q) while it's recording. Relaunch → an alert offers "An earlier recording was interrupted — Synthesize a skill from it now?" → **Synthesize it** → it synthesizes the partial recording and lands in Review. (Choosing **Discard** removes the recovery manifest.)

### Library actions

- [ ] **Open in Finder** opens the skill directory.
- [ ] **Re-open in Review** switches to the Flow tab in Review for that skill.
- [ ] **Delete** (with confirm) removes the skill from `~/.claude/skills/` and the list.
- [ ] Delete a skill directory from Finder, then return to the Library pane → that row is greyed "(missing — removed outside Mengo)" with only a **Remove from list** action.

### Regressions to spot-check

- [ ] The Memory pane still works (record/pause/resume/sources picker); the recorder still starts on launch and stops on quit.
- [ ] `~/Library/Logs/MengoDesktop/` has `app.log`, `recorder.log`, and `synthesis-<id>.log` files; `~/Library/Application Support/MengoDesktop/flows/` has `manifests/` and `library.json` (and `recovery/` only if a recording was interrupted).
