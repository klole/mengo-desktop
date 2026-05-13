# Mengo Desktop — Dark Brand Theme + Logo + Polish

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Follows:** [`2026-05-12-mengo-memory-pane-redesign-design.md`](2026-05-12-mengo-memory-pane-redesign-design.md) (the Memory pane redesign — committed on `mengo/memory-pane-redesign`, not yet merged)
**Branch:** `mengo/memory-pane-redesign` (this work continues on the same branch)

## Goal

Make Mengo Desktop look like a finished product, not "surface-level Swift": adopt the mengo.ai brand palette as a fixed dark theme, bring the mengo.ai mango logo into the app, and add real polish — SF Symbol icons on every action, and tasteful animations (pulsing/glowing recording status, rolling stat numbers, section-switch transitions, hover lifts, banner springs).

This is **part A** of the larger request the user made; **part B** (per-monitor recording selection + audio-source toggles) is a separate, immediately-following spec — explicitly out of scope here.

## Decisions (locked)

- **Palette = the mengo.ai dark palette, verbatim.** No invented shades, no darkening. (The site's `globals.css` is actually a *light* "Sunlit Minimal" theme; we use the dark palette the user specified.)
- **The app is forced to dark appearance** — `NSApp.appearance = NSAppearance(named: .darkAqua)` at launch, so the menu bar dropdown matches the windowed UI. `Theme`'s color values are concrete (not system-dependent), so the panes are the right colors regardless.
- **Recorder state colors** (functional, not part of the brand palette): **recording = green**, **paused = the brand orange (`#FF8A3D`)**, **error = red**.
- **The logo** = `~/Desktop/Mengo.ai/public/logo.png` (the transparent-background mango). Copied into the app and shown as a wordmark in the **sidebar header** (`[mango] Mengo`), replacing the plain `.navigationTitle("Mengo")`.
- **No new product surfaces** — the Memory pane keeps the information architecture from the redesign; this is a restyle + polish, not a re-layout.

## `Theme.swift` — the new tokens

| Token | Value (sRGB) | Use |
|---|---|---|
| `windowBackground` | `#121315` | window + sidebar |
| `paneBackground` | `#17181B` | content panes (with a barely-perceptible `#17181B → #121315` vertical gradient for depth) |
| `cardBackground` | `#1D1F23` | stat tiles, the degraded banner, resting hover surface |
| `elevatedBackground` | `#22242A` | hover state for tiles (one notch above `cardBackground`) |
| `separator` | `#2A2D33` | hairline borders + dividers |
| `primaryText` | `#F3F4F6` | titles, stat numbers |
| `secondaryText` | `#A6ADB8` | body, labels |
| `mutedText` | `#737A86` | captions, low-emphasis text |
| `accent` | `#FF8A3D` | the warm orange — used sparingly: primary-button tint, the logo wordmark, the selected-sidebar-row highlight, a faint glow behind the recording status |
| `accentHover` | `#FF9D5C` | hover tint on accented controls |
| `accentGlow` | `#FF8A3D` @ 18% opacity (`Color(red: 1.0, green: 0.541, blue: 0.239, opacity: 0.18)`) | soft halos / highlight fills |
| `recording` | `#3DD56B` (green) | recorder running |
| `paused` | = `accent` (`#FF8A3D`) | recorder paused (audio/screen/both) |
| `stopped` | `#E5484D` (red) | recorder error |

`Theme`'s typography tokens are unchanged. The previous semantic colours added in the redesign (`recording`/`paused`/`stopped` mapping to `.green`/amber/`.red`, and `cardBackground` mapping to a system colour) are replaced by the values above.

`Theme` colours become hex-literal `Color`s — add a small `Color(hex:)` initialiser (or inline the `red:green:blue:` doubles) so the table above maps 1:1 to the file. The hairline-border look (1 px `separator`-coloured strokes on cards and as `Divider` overlays) is part of "dark-UI crisp."

## The logo in the app

- Copy `~/Desktop/Mengo.ai/public/logo.png` → `Resources/MengoLogo.png` (committed; ~670 KB PNG, 1254×1254 RGBA, transparent margins).
- `build-mengo.sh` copies it into the bundle: `cp Resources/MengoLogo.png "$APP_BUNDLE/Contents/Resources/MengoLogo.png"` (same pattern as `AppIcon.icns`). No `Package.swift` change.
- New `Sources/MengoDesktop/Brand.swift`: `enum Brand { static let logo: Image? = Bundle.main.url(forResource: "MengoLogo", withExtension: "png").flatMap { NSImage(contentsOf: $0) }.map { Image(nsImage: $0) } }` — nil-safe (when run via `swift run` rather than the assembled `.app`, `logo` is `nil` and the wordmark falls back to text only).
- **Placement:** the sidebar header — a pinned row above the section list: `HStack { (Brand.logo ?? Image(systemName: "circle.fill")).resizable().scaledToFit().frame(width: 22, height: 22); Text("Mengo").font(.title3.weight(.bold)).foregroundStyle(Theme.primaryText) }`, padded, on `windowBackground`. The `.navigationTitle` is removed (it'd duplicate). The menu-bar item keeps text + status glyph.

## Restyle

- **Memory pane** (`MemoryPane.swift`) — same information architecture as the redesign (status hero → controls → "this session" tiles → privacy footer), restyled to the dark palette: `paneBackground` with the subtle gradient; stat tiles on `cardBackground` with `separator` hairline borders; `accent` only on the primary "Pause both" button and a faint `accentGlow` halo behind the recording dot; text in the three text greys. **Icons on every action button** via `Label(_, systemImage:)`: `pause.circle.fill` / `play.circle.fill` (Pause/Resume both), `mic` / `mic.slash` (audio), `display` / `display.slash` (screen), `arrow.clockwise` (Restart recorder), `folder` (Reveal recordings), `doc.text` (View log). The hero's status dot/glyph and the menu-bar glyph use the new state colours (green / orange / red).
- **Sidebar** (`MainWindowView.swift`) — `windowBackground`; the logo wordmark header; rows with their existing SF Symbols; the **selected row** gets an `accentGlow` fill behind it and an `accent`-tinted icon (a clearer selection cue than the default).
- **Placeholder panes** (`ComingSoonPane.swift`, used by Flow/Library/Studio/Settings) — restyled to the dark palette; the big section glyph uses `Theme.accent` (now `#FF8A3D`).
- **Menu bar dropdown** (`MenuBarContent.swift`) — `MenuBarLabel` glyph colours come from the new `Theme` state colours; the Memory-group items get small SF Symbol icons (`Button { } label: { Label(_, systemImage:) }` — `NSMenu` renders them).

## Animations

- Recording dot: `.symbolEffect(.pulse)` plus a soft `accentGlow` halo behind it that gently breathes (`scaleEffect`/`opacity` on a `repeatForever` `.easeInOut`).
- Stat numbers: `.contentTransition(.numericText())` + `withAnimation` on `lastHealth` changes — the frame/word counts roll/count as `/health` updates.
- Sidebar section switch: the detail content crossfades + slides a few px (`.transition(.opacity.combined(with: .move(edge: .trailing)))`, wrapped in `withAnimation(.spring(duration: 0.3))` keyed on `appState.selectedSection`); `.id(appState.selectedSection)` on the detail container so SwiftUI treats it as a replace.
- Hero status changes (Starting… → Recording → Paused → Stopped): smooth colour + text crossfade (`.animation(.easeInOut, value: recorder.status)` on the hero block).
- Degraded banner: springs down from the top on appear, springs away when it clears (`.transition(.move(edge: .top).combined(with: .opacity))`).
- Stat tiles: `.onHover` lifts them (`cardBackground` → `elevatedBackground`) with a faint `accent`-tinted border; primary "Pause both" button hover → `accentHover` tint + a tiny `scaleEffect(1.02)`.
- Pane content: a quick staggered fade-in on appear (each section `.opacity`/`.offset` animated in with a small per-index delay), once.

## Components & code changes

| File | Change |
|---|---|
| `Sources/MengoDesktop/Theme.swift` | Replace the colour tokens with the table above (hex-literal `Color`s; add a `Color(hex:)` helper or inline doubles). Keep the typography tokens. |
| `Sources/MengoDesktop/Brand.swift` | **New** — `enum Brand { static let logo: Image? = … }` (nil-safe `Bundle.main` load of `MengoLogo.png`). |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | `AppDelegate.applicationDidFinishLaunching` sets `NSApp.appearance = NSAppearance(named: .darkAqua)` (before/after the recorder start — order doesn't matter). |
| `Sources/MengoDesktop/MainWindowView.swift` | Sidebar logo-wordmark header; selected-row `accentGlow` highlight + accent icon tint; remove `.navigationTitle`; the detail container gets `.id(appState.selectedSection)` + the section-switch transition. |
| `Sources/MengoDesktop/MemoryPane.swift` | Dark-palette restyle; subtle pane gradient; SF Symbol icons on all action buttons; the recording-dot glow halo; `.contentTransition(.numericText())` on the stat numbers; hero status crossfade; degraded-banner spring; stat-tile hover lift; staggered fade-in. |
| `Sources/MengoDesktop/ComingSoonPane.swift` | Dark-palette restyle (mostly automatic via the new `Theme` values; verify the big glyph + text read well on `paneBackground`). |
| `Sources/MengoDesktop/MenuBarContent.swift` | `MenuBarLabel` already reads `Theme` state colours (they're new now); add SF Symbol icons to the Memory-group menu items. |
| `Resources/MengoLogo.png` | **New** — copied from `~/Desktop/Mengo.ai/public/logo.png`. |
| `build-mengo.sh` | Add `cp Resources/MengoLogo.png "$APP_BUNDLE/Contents/Resources/MengoLogo.png"` in the assembly step (next to the `AppIcon.icns` generation). |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | Update the "App behaviour" section: dark theme everywhere (window, panes, menu); the mango logo in the sidebar header; action buttons have icons; the recording dot pulses + has a soft halo; stat numbers roll when they change; switching sidebar sections crossfades; recording=green / paused=orange / error=red. |

No `Package.swift` change. No new Swift unit tests (colours, the logo bundle, and animations aren't unit-testable here); `swift build` + `swift test` (the existing 73) stay the gate, plus the updated manual smoke checklist.

## Out of scope

- **Part B** — per-monitor recording selection and audio-source toggles (`-m`/`-i`/`--disable-audio` plumbing, a "Capture" section in the Memory pane, recorder-restart-on-change). Next spec.
- The activity timeline / memory search (Phase 2.5 / Pro).
- Renaming `~/.screenpipe/` (locked).
- Animating the mango itself (the website has a posed/animated `Mango` component) — we use the static PNG.
- A Settings/About pane (Phase 4) — the logo lives only in the sidebar header for now.

## Open questions for the implementation plan

- **`build-mengo.sh` & `swift run`**: the logo only resolves from the assembled `.app` (`Bundle.main`). That's fine — the app always ships as the `.app`; in `swift run` the wordmark is text-only. If a dev wants the logo in `swift run` too, the alternative is a SwiftPM resource (`resources:` on the target + `Bundle.module`) — not worth it now.
- **Forced dark + `MenuBarExtra(.menu)`**: `NSApp.appearance = .darkAqua` should darken the menu too; verify during the plan. If the menu still follows the system, leave it — the windowed UI is the priority.
- **Animation restraint**: if the staggered fade-in or the breathing-halo feels gimmicky on a real run, dial it back. The pulse + numeric-text roll + section crossfade are the keepers.
- **Exact green/red**: `recording = #3DD56B`, `stopped = #E5484D` are starting values; tune against the real dark background if they don't pop.
