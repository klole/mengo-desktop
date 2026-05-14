# Manual Smoke Test — Mengo Desktop Phase 2 ("Mengo Memory")

Run before tagging `mengo-v2-phase-2-memory`. Spec:
`docs/superpowers/specs/2026-05-12-mengo-phase-2-memory-design.md`.

## Build & tests (scriptable)

- [ ] `swift build` — all targets compile.
- [ ] `swift test` — all tests pass (Phase 1's + Phase 2's).
- [ ] `./build-mengo.sh` — completes; prints `screenpipe vX.Y.Z (arch) embedded`; produces `MengoDesktop.app` + `.zip`. (Needs network for the screenpipe download.)
- [ ] `MengoDesktop.app/Contents/Helpers/{screenpipe,mlx.metallib}` exist; both codesigned with `Identifier=ai.mengo.desktop` (`codesign -dv`); `codesign --verify --deep --strict MengoDesktop.app` passes.
- [ ] `Info.plist` has `NSMicrophoneUsageDescription`, `NSScreenCaptureUsageDescription`, `NSAllowsLocalNetworking`; `LSUIElement = false`.

## App behaviour (run `open MengoDesktop.app` — needs a human at the machine)

- [ ] The whole app is **dark** — window, sidebar, content panes, and the menu-bar dropdown all on the mengo.ai dark palette (`#121315`/`#17181B`/`#1D1F23`), not the system light theme.
- [ ] The **sidebar header** shows the mango logo + "Mengo" wordmark; the selected sidebar row is highlighted in the brand orange.
- [ ] Every action button has an **icon** — Pause both / Pause audio / Pause screen (a crossed-rectangle glyph, not a blank gap) / Restart recorder / Reveal recordings / Configure sources… — in the Memory pane, and Pause both / Pause audio / Pause screen / Reveal recordings / View log in the menu.
- [ ] The recording dot **pulses** with a soft green halo; the "This session" numbers **roll** when `/health` updates; switching sidebar sections **crossfades**; hovering a stat tile **lifts** it.
- [ ] Recorder state reads **green = recording**, **orange = paused**, **red = error** — in the hero, the menu-bar glyph, and the pane.
- [ ] Screen Recording + Microphone permission dialogs appear; grant both (toggle Mengo Desktop on in System Settings if prompted).
- [ ] Within ~15 s the menu-bar glyph turns **green**. The Memory pane shows **one** status dot (no duplicate `●`), "Recording", the "everything stays on this Mac" subtitle, and a "Since … · …" uptime line.
- [ ] No "Screen capture: ok / Audio capture: ok" rows anywhere — capture-status text appears *only* if `/health` reports a degraded status (then an amber banner shows).
- [ ] "This session" shows four **equal-height** stat tiles — screens captured / words transcribed / displays / mic sources — with plausible numbers that climb over time; "Last capture · just now"; "Recordings folder · N GB" once the size is computed.
- [ ] **Pause both** (pane or menu) → menu-bar glyph amber, pane shows "Paused", the button reads "Resume both"; clicking it → back to green "Recording". Pause audio / Pause screen individually still work too.
- [ ] **Reveal recordings** opens `~/.screenpipe/` in Finder — and that folder path is *not* shown anywhere in the UI.
- [ ] The Memory pane has **no "View log"** link; "View log" is in the menu-bar dropdown and opens `~/Library/Logs/MengoDesktop/recorder.log`.

### Recording sources (Memory pane)

- [ ] **Configure sources…** opens a sheet — a brief spinner ("Looking for displays and microphones…"), then a row of display thumbnails (drawn to each display's aspect ratio, name + resolution below, "Main" on the default) and an "Audio sources" card with a toggle per device.
- [ ] The displays / mics **currently being recorded** are pre-selected — orange ring + checkmark on those display thumbnails, toggle on for those audio devices.
- [ ] **Apply & restart recording** is disabled until the selection changes; deselecting a display, then Apply → the sheet closes, the pane shows "Starting…" then "Recording", and `curl -s localhost:3030/health | python3 -c 'import json,sys; print(json.load(sys.stdin)["monitors"])'` lists only the kept display(s); the "displays" stat tile matches.
- [ ] Trying to deselect the **last remaining display** does nothing (it stays selected).
- [ ] Open the sheet again, turn **off all audio toggles** (an amber "microphone capture will be off" note appears), Apply → recording resumes **video-only**: the pane shows "Microphone off — no audio sources selected" in place of the Pause-audio button, `/health` audio devices are empty, the "mic sources" tile reads 0.
- [ ] Re-enable all audio + all displays, Apply → back to the original behaviour (the "Microphone off" note is gone, Pause-audio button is back).
- [ ] Quit the app, **unplug an external display**, relaunch → no crash; the pane reads "Recording" with the built-in display only (the stored selection that referenced the unplugged display fell back to "all").
- [ ] Nothing in the Memory pane or the menu says "screenpipe" or shows an engine version.
- [ ] `~/.screenpipe/` fills with data; `~/Library/Logs/MengoDesktop/recorder.log` has screenpipe output.
- [ ] `pkill screenpipe` → within ~30 s the pane shows "⚠ Recorder stopped" + the reason + a prominent **Restart recorder** button; clicking it (or the menu "Restart recorder") brings it back to green.
- [ ] Close the main window → app stays in the Dock, glyph still green (recording continues).
- [ ] **Quit** (⌘Q / menu) → app exits; `pgrep screenpipe` shows no orphan; `~/Library/Logs/MengoDesktop/app.log` has `app terminating`.

## Memory Dashboard (the 2026-05-14 rewrite)

The dashboard supersedes the old debug-screen Memory pane. The right-rail
activity feed appears only when the window is ≥ 1100 pt wide — narrower
windows tuck it under Top Applications.

### Hero

- [ ] The orange orb is **always orange** (Mengo brand). It scales + glows
  in a slow pulse only while the recorder is actively running.
- [ ] Activity pill reflects state:
  `Memory Inactive` (red) → `Starting…` (orange) → `Memory Active` (green)
  → `Memory Paused` (amber) → `Memory Error` (red).
- [ ] Status word + subtitle (`Mengo is sleeping` / `…watching` / `…paused` /
  `…hit a snag`) follow `recorder.status`.
- [ ] **Start Watching** button switches label/icon by state:
  Start Watching → Stop Watching → Resume → Starting… (disabled spinner).
- [ ] **Monitors** pill opens a menu populated from `/health` `monitors`;
  **Audio sources** from `audio_pipeline.audio_devices`. Each menu's last
  item ("More options…") opens the existing `RecordingSourcesView` sheet.
- [ ] **Capture mode** pill cycles through Smart Capture / Changes only /
  Periodic. Picking a different mode while recording restarts the recorder
  with the new `--fps` flag (verify in
  `~/Library/Logs/MengoDesktop/recorder.log`).
- [ ] **Settings gear** routes to the Settings tab.

### Mengo Insights carousel

- [ ] On a fresh DB (no recorded activity yet) the carousel renders an
  empty-state card with the "Mengo will surface patterns here." copy.
- [ ] After several hours of activity, the carousel shows up to 4 cards:
  Workflow Detected / Automation Opportunity / Memory Insight / Focus
  Pattern. Each card has a CTA button (Create Skill / Create Flow / View
  Memory / See Details) that routes appropriately.
- [ ] With **Settings → Generate insight summaries with AI** off (default),
  card bodies use templated text. With it on, the next refresh (≤10 min)
  rewrites the bodies via the user's Claude Code / Codex CLI; the cached
  result lands at `~/Library/Application Support/MengoDesktop/insights-cache.json`.

### Recent Sessions

- [ ] Up to 3 session tiles: 3-app icon stack + "<Dominant App> session"
  title + optional subtitle (dominant window name OR "with <SecondApp>")
  + duration + frame count + Open Session button.
- [ ] **View All Sessions** opens the sessions list sheet.

### Top Applications

- [ ] Horizontal bars per app, orange capsule width proportional to share %.
  Picker toggles Today / Last 7 days / Last 30 days; selection persists
  across launches.
- [ ] **View All Applications** opens the apps list sheet.

### Quick Actions

- [ ] Five tiles route correctly:
  - Configure Sources → opens the advanced sources sheet
  - Create Flow → Flow tab
  - Train New Skill → Flow tab
  - Open Studio → Studio tab (Pro) or `/upgrade` (Free, via web-handoff)
  - Import Workflow → file picker (.json); selection is logged

### Activity feed (right rail / tucked-under)

- [ ] **Live** dot pulses; a new screenshot / transcription within the last
  5 s lands at the top with the right icon (camera / waveform / globe).
- [ ] Below the 1100 pt width threshold, the rail collapses below Top Apps —
  nothing is lost.
- [ ] **View All Activity** opens the activity list sheet.

### Schedule Recording

- [ ] Hero's **Schedule Recording** button opens the sheet.
- [ ] Add a recurring rule (today's weekday, 1 min from now → 2 min from now).
  Wait — the recorder auto-pauses at the end of the window. Add a fresh
  rule starting now → it auto-resumes within ~5 s of the next health tick.
- [ ] Delete a rule from the sheet → it stops enforcing.
- [ ] An empty schedule does not pause / resume the recorder.

### Settings → Generate insight summaries with AI

- [ ] Toggle visible under Startup. Default off. Caption explains the 10-min
  cache + per-launch behaviour.
