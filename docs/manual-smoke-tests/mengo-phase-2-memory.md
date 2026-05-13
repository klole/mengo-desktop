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

- [ ] Screen Recording + Microphone permission dialogs appear; grant both (toggle Mengo Desktop on in System Settings if prompted).
- [ ] Within ~15 s the menu-bar glyph turns **green**. The Memory pane shows **one** status dot (no duplicate `●`), "Recording", the "everything stays on this Mac" subtitle, and a "Since … · …" uptime line.
- [ ] No "Screen capture: ok / Audio capture: ok" rows anywhere — capture-status text appears *only* if `/health` reports a degraded status (then an amber banner shows).
- [ ] "This session" shows four stat tiles — screens captured / words transcribed / displays / mic sources — with plausible numbers that climb over time; "Last capture · just now"; "Recordings folder · N GB" once the size is computed.
- [ ] **Pause both** (pane or menu) → menu-bar glyph amber, pane shows "Paused", the button reads "Resume both"; clicking it → back to green "Recording". Pause audio / Pause screen individually still work too.
- [ ] **Reveal recordings** opens `~/.screenpipe/` in Finder — and that folder path is *not* shown anywhere in the UI.
- [ ] **View log** opens `~/Library/Logs/MengoDesktop/recorder.log` (pane and menu both work).
- [ ] Nothing in the Memory pane or the menu says "screenpipe" or shows an engine version.
- [ ] `~/.screenpipe/` fills with data; `~/Library/Logs/MengoDesktop/recorder.log` has screenpipe output.
- [ ] `pkill screenpipe` → within ~30 s the pane shows "⚠ Recorder stopped" + the reason + a prominent **Restart recorder** button; clicking it (or the menu "Restart recorder") brings it back to green.
- [ ] Close the main window → app stays in the Dock, glyph still green (recording continues).
- [ ] **Quit** (⌘Q / menu) → app exits; `pgrep screenpipe` shows no orphan; `~/Library/Logs/MengoDesktop/app.log` has `app terminating`.
