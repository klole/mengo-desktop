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
- [ ] Within ~15 s the menu-bar glyph turns **green** and the Memory pane shows "● Recording" + `screenpipe vX.Y.Z`.
- [ ] `~/.screenpipe/` starts filling with data; `~/Library/Logs/MengoDesktop/recorder.log` has screenpipe output.
- [ ] Menu **Pause audio** → glyph yellow, pane shows "Audio paused"; **Resume audio** → green again.
- [ ] Menu **Pause screen** → `pgrep screenpipe` shows the process gone, glyph yellow, pane "Screen paused"; **Resume screen** → process back, glyph green.
- [ ] **Open data folder** opens `~/.screenpipe/`; **Open recorder log** opens `recorder.log` (menu and Memory pane both work).
- [ ] `pkill screenpipe` → within ~30 s glyph **red**, pane shows the error + a **Restart recorder** button; clicking it (or the menu "Restart recorder") brings it back to green.
- [ ] Close the main window → app stays in the Dock, glyph still green (recording continues).
- [ ] **Quit** (⌘Q / menu) → app exits; `pgrep screenpipe` shows no orphan; `~/Library/Logs/MengoDesktop/app.log` has `app terminating`.
