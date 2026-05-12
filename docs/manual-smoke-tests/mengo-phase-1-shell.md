# Manual Smoke Test — Mengo Desktop Phase 1 ("The Shell")

Run this before tagging `mengo-v2-phase-1-shell`. Spec:
`docs/superpowers/specs/2026-05-12-mengo-phase-1-shell-design.md`.

## Build & tests (scriptable)

- [ ] `swift build` — all targets compile (`ScreenpipeMenu`, `ScreenpipeFlow`, `MengoDesktop`).
- [ ] `swift test` — all tests pass.
- [ ] `./build-mengo.sh` — completes, produces `MengoDesktop.app` and `MengoDesktop.zip`.
- [ ] `MengoDesktop.app/Contents/Resources/AppIcon.icns` exists; `Info.plist` has `CFBundleIdentifier = ai.mengo.desktop` and `LSUIElement = false`.

## App behaviour (run `open MengoDesktop.app`)

- [ ] A **Dock icon** (the mango) appears, and the app shows up in ⌘-Tab.
- [ ] The main window opens with a sidebar of exactly five rows — Memory, Flow, Library, Studio (with a "Pro" badge), Settings — and the **Memory** pane selected.
- [ ] Each pane shows: a large glyph, the section name, "Coming in Phase N" (Memory→2, Flow→3, Library→3, Settings→4, Studio→5), and a one-line blurb.
- [ ] Clicking each sidebar row swaps the detail pane to that section.
- [ ] A **menu bar item** labelled "Mengo" appears. Opening it shows: a "Mengo" header; a "Memory" group (Pause audio / Pause screen / Open data folder — all greyed out); a "Flow" group (Start recording… / Grab last 5 minutes… — greyed out); then Library, Studio (Pro), Settings…; then Quit Mengo Desktop (⌘Q).
- [ ] Clicking **Library** / **Studio (Pro)** / **Settings…** in the menu brings the main window to the front with that section selected.
- [ ] **Quit** (menu item or ⌘Q) terminates the app cleanly.
- [ ] `~/Library/Logs/MengoDesktop/app.log` exists and contains an `app launched, pid=…` line and an `app terminating` line.
