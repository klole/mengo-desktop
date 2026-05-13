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
