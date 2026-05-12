# Mengo Desktop — Phase 1: "The Shell" Design

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Playbook:** [`2026-05-12-mengo-desktop-playbook.md`](2026-05-12-mengo-desktop-playbook.md) → Phase 1
**Branch:** `mengo/phase-1-shell`

## Goal

A launchable Mengo Desktop app: a Dock-icon macOS app with one main window
(left-sidebar navigation across Memory / Flow / Library / Studio / Settings)
and a single menu bar dropdown. No recording, no synthesis, no licensing —
every pane is a placeholder ("Memory — coming in Phase 2"). This phase
establishes the app skeleton, the design system, the build/packaging
pipeline, and the lifecycle hooks that Phases 2–5 plug into.

This is the first of the five phases in the Mengo Desktop playbook. It is
greenfield — it adds a new `Sources/MengoDesktop/` target alongside the V1
apps (`ScreenpipeMenu`, `ScreenpipeFlow`) and touches neither of their source
trees.

## Decisions (locked)

| Topic | Decision | Notes |
|---|---|---|
| Codebase location | Stay in this repo; add `Sources/MengoDesktop/`. | Playbook option (b). V1 source kept intact as historical/port reference. Repo rename deferred to V2 cleanup. |
| Dock icon vs menu-bar-only | **Dock icon** — `LSUIElement = false`. | Full windowed app: Dock icon, ⌘-Tab visible, main window, *plus* a menu bar item alongside (Things/Fantastical-style). |
| Window layout | **Left sidebar** via `NavigationSplitView`. | Like System Settings / Mail / Xcode. Tab bar cramps at 5 items; multi-window is the V1 pattern V2 is collapsing. |
| App icon | **User-provided art.** Source at `mengo-app-icon.png` (1254×1254 RGBA, app-icon-styled). | Moves to `Resources/AppIcon.png` during implementation; `build-mengo.sh` generates `AppIcon.icns` from it. No binary `.icns` committed. |
| V1 code reuse | **Pull just-in-time per phase**, not wholesale. | Phase 1 records/synthesizes nothing, so wholesale-copying V1's ~12 recording/synthesis files would drop dead, soon-rewritten code into the shell. V1 source is the reference. The one thing Phase 1 lifts: a minimal logger drawing on V1's logging patterns (`ScreenpipeFlow/Logger.swift` plus the stdout-redirect in `ScreenpipeMenuApp.init`). |
| Bundle identity | Name `Mengo Desktop`, id `ai.mengo.desktop`, menu-bar label `Mengo`. | New `Resources/MengoDesktopInfo.plist`, new `build-mengo.sh`. |
| Tech stack | Swift 6 / SwiftUI, SwiftPM, macOS 15+, ad-hoc (or self-signed dev cert) codesign. | Matches V1's `ScreenpipeMenu`/`ScreenpipeFlow` baseline. Build universal (arm64 + x86_64) for parity with `build-flow.sh`; arm64 is the supported target. |
| SwiftUI structure | `MenuBarExtra` (`.menu` style) + a single `Window` scene. | No HUD in Phase 1. `WindowGroup` is *not* used — a singleton `Window` avoids ⌘N window proliferation for this Settings-app-style app. |
| Design-system accent | Warm orange sampled from the provided icon (≈ `#FB8420`, gradient ≈`#FD9A1E`→`#F96B1B`). | The app and its icon read as one identity. Exact value pinned in `Theme.swift` at implementation time; revisitable if a fuller mengo.ai brand kit lands. |

## In scope for Phase 1

- New executable target `MengoDesktop` (`@main` SwiftUI `App`) + `MengoDesktopTests`.
- Main window: `NavigationSplitView` with a five-row sidebar (Memory / Flow /
  Library / Studio / Settings); each row shows a placeholder "coming in
  Phase N" pane in the detail column.
- Single `MenuBarExtra` dropdown laid out per the playbook sketch — Memory and
  Flow sections present but disabled; Library / Studio / Settings navigate the
  main window; Quit works. Menu-bar label is static (`Mengo` + a neutral
  glyph) — no recording status.
- `applicationWillTerminate` plumbing via an `NSApplicationDelegate` (logs
  "app terminating"; the seam Phase 2 hooks recorder shutdown into).
- Design system defined once: `Theme.swift` — accent + semantic colors + a
  small type scale.
- App-icon pipeline: commit the source PNG; `build-mengo.sh` generates the
  `.icns`; `Info.plist` references it.
- Packaging: `Resources/MengoDesktopInfo.plist`, `build-mengo.sh` (mirrors
  `build-flow.sh`), `.gitignore` entries, and the `Package.swift` target
  additions.
- A minimal file logger (`Log.swift`) writing to
  `~/Library/Logs/MengoDesktop/app.log`.
- `docs/manual-smoke-tests/mengo-phase-1-shell.md` — the checklist to run
  before tagging `mengo-v2-phase-1-shell`.

## Explicitly NOT in Phase 1

| Deferred to | Item |
|---|---|
| Phase 2 | Any screenpipe recording; the recorder lifecycle; pause/resume; "Open data folder"; TCC permission prompts; `NSAllowsLocalNetworking`; menu-bar recording status. |
| Phase 3 | Flow recording, the floating HUD, synthesis (`claude -p`), Timeline/Review/Library *content*, the ⌃⌥R / ⌃⌥G global hotkeys. |
| Phase 4 | Accounts, license validation, Free/Pro gating (Studio's "(Pro)" tag in Phase 1 is a static label, not gating logic), `mengo://` deep links, the runtime selector. |
| Phase 5 | Studio's node-graph editor and Replay. |
| Out of scope | Notarization; Mac App Store packaging; Intel/Windows builds; an asset catalog (`.xcassets`) — Phase 1 uses code-defined design tokens, matching V1. |

## Architecture

`MengoDesktop` is a single Swift app process. Phase 1 is eight small files
under `Sources/MengoDesktop/`, organized by lifecycle / state / UI / support.

```
┌──────────────────────────────────────────────────────────────┐
│  MengoDesktopApp  (@main App)                                │
│   ├─ AppDelegate (in-file)  →  applicationWillTerminate        │
│   ├─ @State appState: AppState                                │
│   ├─ Scene: Window("Mengo Desktop", id: "main")               │
│   │           └─ MainWindowView(appState)                     │
│   │                ├─ sidebar:  List(SidebarSection.allCases)  │
│   │                └─ detail:   ComingSoonPane(section)        │
│   └─ Scene: MenuBarExtra { MenuBarContent(appState) }          │
│                label: { "Mengo" + neutral glyph }             │
└──────────────────────────────────────────────────────────────┘
        Theme.swift  ── design tokens (colors, type scale)
        Log.swift    ── file logger → ~/Library/Logs/MengoDesktop/app.log
```

### File layout (`Sources/MengoDesktop/`)

| File | Responsibility | Depends on |
|---|---|---|
| `MengoDesktopApp.swift` | `@main` SwiftUI `App`. Calls `Log.bootstrap()` in `init()`. Declares the `Window` scene and the `MenuBarExtra` scene. Owns `@State private var appState = AppState()`. Contains the small `AppDelegate` class (`@NSApplicationDelegateAdaptor`) with `applicationWillTerminate` → `Log.line("app terminating")`. | `AppState`, `MainWindowView`, `MenuBarContent`, `Log` |
| `AppState.swift` | `@MainActor @Observable final class`. Phase 1 holds exactly one thing: `selectedSection: SidebarSection` (default `.memory`) — the binding the sidebar `List` and the menu's nav entries both drive. No methods in Phase 1. The seam Phases 2–4 extend (recorder status, Flow session, account state). | `SidebarSection` |
| `SidebarSection.swift` | `enum SidebarSection: String, CaseIterable, Identifiable` — `case memory, flow, library, studio, settings`. Computed: `displayName`, `systemImage` (an SF Symbol per section), `phase: Int` — the phase that fills it in (memory→2, flow→3, library→3, studio→5, settings→4), `comingSoonBlurb: String`. Pure data; no UIKit/AppKit. | — |
| `MainWindowView.swift` | The `NavigationSplitView`. Sidebar: `List(SidebarSection.allCases, selection: $appState.selectedSection)` rendering `Label(section.displayName, systemImage: section.systemImage)`. Detail: `ComingSoonPane(section: appState.selectedSection)`. Sidebar shows the "Mengo" wordmark at the top; window title "Mengo Desktop". | `AppState`, `SidebarSection`, `ComingSoonPane`, `Theme` |
| `ComingSoonPane.swift` | One parametrized placeholder view: `init(section: SidebarSection)`. Renders a large `Image(systemName: section.systemImage)` tinted with `Theme.accent`, the section name, "Coming in Phase \(section.phase)", and `section.comingSoonBlurb`, centered. Reused for all five rows. | `SidebarSection`, `Theme` |
| `MenuBarContent.swift` | The dropdown `View` (layout below). Buttons in the Memory and Flow sections are `.disabled(true)` in Phase 1 (no backing methods needed). The Library / Studio / Settings buttons set `appState.selectedSection` and raise the main window — `@Environment(\.openWindow) openWindow; openWindow(id: "main")` plus `NSApp.activate(ignoringOtherApps: true)`. Quit calls `NSApplication.shared.terminate(nil)`. Also exports the inline menu-bar label (`"Mengo"` + a neutral SF Symbol such as `circle.dotted`). | `AppState`, `SidebarSection` |
| `Theme.swift` | Design-system tokens. `enum Theme` with `static let accent: Color` (the icon orange, ≈ `#FB8420`), semantic colors (`windowBackground`, `paneBackground`, `separator`, `primaryText`, `secondaryText` — most mapping to system `NSColor`s so the app respects light/dark/accessibility), and a `Typography` sub-enum or `Font` helpers (`largeTitle`, `title`, `headline`, `body`, `caption` with weights). A comment marks the concrete values as starter values, swappable when a fuller brand kit exists. | — |
| `Log.swift` | Minimal file logger drawing on V1's logging patterns. `enum Log { static func bootstrap(); static func line(_ msg: String); static var fileURL: URL }`. `bootstrap()` creates `~/Library/Logs/MengoDesktop/`, redirects `stdout`/`stderr` to `app.log` (the `ScreenpipeMenuApp.init` pattern — Finder-launched apps have no terminal), and writes a launch line; `line(_:)` appends a timestamped line (the `ScreenpipeFlow/Logger` shape). `try?` swallows directory-creation failure (matches V1). Called from `MengoDesktopApp.init()`. | — |

### Data flow

Phase 1 has essentially one interaction:

1. **Sidebar selection.** User clicks a sidebar row → SwiftUI updates
   `appState.selectedSection` → `MainWindowView`'s detail column re-renders
   `ComingSoonPane` for the new section.
2. **Menu navigation.** User clicks Library / Studio / Settings in the menu
   bar dropdown → the button sets `appState.selectedSection = .library`, calls
   `openWindow(id: "main")` (creates the window if it was closed, raises it if
   not) and `NSApp.activate(ignoringOtherApps: true)` → the main window comes
   forward showing the right pane.
3. **Quit.** Menu Quit → `terminate(nil)` → `AppDelegate.applicationWillTerminate`
   logs and the process exits.

### Error handling

There is no meaningful error surface in the shell. The only I/O is the log
file; if `~/Library/Logs/MengoDesktop/` can't be created, `try?` swallows it
and logging silently no-ops (identical to V1). No network, no subprocesses, no
file parsing in Phase 1.

## UI surfaces

### Main window

A single non-document `Window(id: "main")` titled "Mengo Desktop", using
`NavigationSplitView` with a collapsible sidebar. Default selection: Memory.

```
┌──────────────────┬────────────────────────────────────────┐
│  Mengo           │                                        │
│                  │            [  🧠 glyph  ]               │
│  ▸ Memory        │                                        │
│    Flow          │               Memory                   │
│    Library       │                                        │
│    Studio  (Pro) │   Coming in Phase 2 — always-on local  │
│    Settings      │   recording of your screen, mic, and   │
│                  │   accessibility tree.                  │
│                  │                                        │
└──────────────────┴────────────────────────────────────────┘
```

- Five rows, each → its `ComingSoonPane(section:)`.
- The "(Pro)" suffix on Studio is a static string in the row label — there is
  no licensing/gating logic in Phase 1.
- SF Symbols (indicative; finalize in implementation): Memory `brain` /
  `clock.arrow.circlepath`; Flow `wand.and.stars` / `record.circle`; Library
  `books.vertical`; Studio `slider.horizontal.below.rectangle` /
  `point.3.connected.trianglepath.dotted`; Settings `gearshape`.
- `comingSoonBlurb` per section, one line each — e.g. Memory: "Always-on
  local recording of your screen, mic, and accessibility tree."; Library:
  "Your saved flows — re-open, rename, delete."; Studio: "A visual editor for
  your flows, plus replay."; Settings: "Capture, storage, hotkeys, account,
  privacy."

### Menu bar dropdown

`MenuBarExtra` with `.menuBarExtraStyle(.menu)`. The label in the menu bar
itself is `"Mengo"` plus a neutral SF Symbol (e.g. `circle.dotted`) — no
status colors, since recording is Phase 2.

```
Mengo
──────────────────────
Memory
  Pause audio                  (disabled)
  Pause screen                 (disabled)
  Open data folder             (disabled)
Flow
  Start recording…             (disabled)
  Grab last 5 minutes…         (disabled)
──────────────────────
Library                        → raises main window, selects Library
Studio  (Pro)                  → raises main window, selects Studio
Settings…                      → raises main window, selects Settings
──────────────────────
Quit Mengo Desktop      ⌘Q
```

- The Memory and Flow groups are rendered (so the user sees the eventual
  shape) but every item is `.disabled(true)` — the products don't exist yet,
  no action fires, and **no global hotkeys are registered** in Phase 1
  (⌃⌥R / ⌃⌥G arrive in Phase 3 with Flow). Section headers ("Memory",
  "Flow") are non-interactive `Text` rows, matching V1's menu style.
- Library / Studio / Settings buttons set `appState.selectedSection` and then
  raise the main window (`openWindow(id: "main")` + `NSApp.activate(...)`).
- Quit calls `NSApplication.shared.terminate(nil)` with `.keyboardShortcut("q")`.

## Design system

`Theme.swift` defines the tokens once so later phases don't each invent
colors. Code-defined (no asset catalog — V1 has none, and `.xcassets` under
SwiftPM requires `.process` resources and a generated accessor for marginal
benefit here).

- **Accent**: the icon's warm orange. Single value ≈ `#FB8420` (mid-gradient
  between the icon's ≈`#FD9A1E` top and ≈`#F96B1B` bottom). A gradient
  variant may be offered for large surfaces; the flat accent is the default.
- **Semantic colors**: `windowBackground`, `paneBackground`, `separator`,
  `primaryText`, `secondaryText` — mostly thin wrappers over system
  `NSColor`s (`.windowBackgroundColor`, `.separatorColor`, `.labelColor`,
  `.secondaryLabelColor`) so light/dark/increase-contrast all work for free.
- **Type scale**: `largeTitle` / `title` / `headline` / `body` / `caption`,
  each a `Font` with an explicit weight, built on the system font. (No custom
  font bundling in Phase 1.)

Concrete hex/weight values are starter values; a comment in `Theme.swift`
says so. If a fuller mengo.ai brand kit (typeface, extended palette) becomes
available, this file is the single place to update.

## App icon pipeline

- The user has provided the artwork: `mengo-app-icon.png`, 1254×1254 RGBA,
  already styled as an app icon (rounded-rect shape + transparent margins).
- During implementation it moves to `Resources/AppIcon.png` — the committed
  single source of truth. No binary `.icns` is committed.
- `build-mengo.sh` generates the icon at build time:
  1. `mkdir AppIcon.iconset` (temp)
  2. `sips -z <h> <w> Resources/AppIcon.png --out AppIcon.iconset/icon_<size>.png`
     for the ten standard entries: `icon_16x16`, `icon_16x16@2x`,
     `icon_32x32`, `icon_32x32@2x`, `icon_128x128`, `icon_128x128@2x`,
     `icon_256x256`, `icon_256x256@2x`, `icon_512x512`, `icon_512x512@2x`
     (i.e. 16, 32, 32, 64, 128, 256, 256, 512, 512, 1024 px — all downscales
     from 1254).
  3. `iconutil -c icns AppIcon.iconset -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"`
  4. `rm -rf AppIcon.iconset`
- `MengoDesktopInfo.plist` sets `CFBundleIconFile = AppIcon`. If
  `Resources/AppIcon.png` is somehow missing, `build-mengo.sh` warns and
  builds with the system default — a missing icon never blocks the build.

## Packaging

### `Resources/MengoDesktopInfo.plist` (new)

Minimal — Phase 1 needs no TCC strings (records nothing) and no local
networking (calls nothing):

```xml
CFBundleDevelopmentRegion        en
CFBundleExecutable               MengoDesktop
CFBundleIdentifier               ai.mengo.desktop
CFBundleInfoDictionaryVersion    6.0
CFBundleName                     Mengo Desktop
CFBundlePackageType              APPL
CFBundleShortVersionString       0.1.0
CFBundleVersion                  1
CFBundleIconFile                 AppIcon
LSMinimumSystemVersion           15.0
LSUIElement                      false        ← Dock icon
NSHighResolutionCapable          true
```

Phase 2 will add `NSMicrophoneUsageDescription`, `NSScreenCaptureUsageDescription`
(and friends), and `NSAppTransportSecurity → NSAllowsLocalNetworking`.

### `build-mengo.sh` (new)

Mirrors `build-flow.sh`:

1. `swift build -c release --arch arm64 --arch x86_64 --product MengoDesktop`
2. Assemble `MengoDesktop.app/Contents/{MacOS,Resources}`; copy the built
   binary; copy `Resources/MengoDesktopInfo.plist` → `Contents/Info.plist`.
3. Generate `AppIcon.icns` from `Resources/AppIcon.png` (steps above) into
   `Contents/Resources/`.
4. Codesign: use the self-signed `ScreenpipeMenu Local Dev` cert if present
   (stable identity across rebuilds → TCC grants survive; relevant for later
   phases) else ad-hoc `-`; `--identifier ai.mengo.desktop`.
5. `ditto -c -k --sequesterRsrc --keepParent MengoDesktop.app MengoDesktop.zip`.

No screenpipe-binary embedding, no `Contents/Helpers/`, no nested-binary
signing — those land in Phase 2 (mirroring `build.sh`).

### `Package.swift` (edited — the only existing-file change)

Add to `targets`:

```swift
.executableTarget(
    name: "MengoDesktop",
    path: "Sources/MengoDesktop"
),
.testTarget(
    name: "MengoDesktopTests",
    dependencies: ["MengoDesktop"],
    path: "Tests/MengoDesktopTests"
)
```

No `resources:` clause — the shell bundles no SwiftPM resources (the icon
goes into the `.app` via `build-mengo.sh`, not via SwiftPM). The existing
`ScreenpipeMenu` / `ScreenpipeFlow` target definitions are not modified.

### `.gitignore` (edited)

Add `MengoDesktop.app/` and `MengoDesktop.zip` alongside the existing
`ScreenpipeMenu`/`ScreenpipeFlow` entries.

## Testing strategy

A shell carries little logic; tests scale accordingly.

### Swift unit tests (XCTest — `Tests/MengoDesktopTests/`)

- **`SidebarSectionTests`**: `allCases` has exactly five members in the
  expected order (memory, flow, library, studio, settings); every case has a
  non-empty `displayName`, a non-empty `systemImage`, a non-empty
  `comingSoonBlurb`, and a `phase` in `2...5`; `id` round-trips.
- **`AppStateTests`**: a fresh `AppState` has `selectedSection == .memory`
  (the app opens on Memory); the property is settable and the change sticks.

(SwiftUI view rendering is not unit-tested — there is no snapshot
infrastructure in this repo. View correctness is covered by the manual smoke
checklist.)

### Manual smoke checklist — `docs/manual-smoke-tests/mengo-phase-1-shell.md`

The list the playbook's working-pattern step 5 wants before tagging
`mengo-v2-phase-1-shell`:

- `./build-mengo.sh` succeeds; `MengoDesktop.app` and `.zip` are produced.
- Launching the app shows a **Dock icon** (the mango) and a ⌘-Tab entry.
- The main window opens with a five-row sidebar (Memory / Flow / Library /
  Studio / Settings) and the Memory pane selected.
- Clicking each sidebar row swaps the detail pane to that section's
  "Coming in Phase N" placeholder.
- A **menu bar item** ("Mengo") appears; opening it shows the dropdown with
  Memory and Flow items present but greyed out, and Library / Studio /
  Settings / Quit active.
- Clicking Library / Studio / Settings in the menu raises the main window and
  selects that pane.
- Quit (menu, or ⌘Q) terminates the app cleanly.
- `~/Library/Logs/MengoDesktop/app.log` exists and contains a launch line and
  a "app terminating" line.

## Seams left for Phases 2–5

| Phase 1 artifact | Picked up by |
|---|---|
| `AppState` (`@Observable`) | Phase 2 adds recorder status + pause/resume state; Phase 3 adds Flow session state; Phase 4 adds account/license state. |
| `AppDelegate.applicationWillTerminate` | Phase 2 hooks screenpipe shutdown into it. |
| `MainWindowView` + `SidebarSection` | Later phases replace each `ComingSoonPane` with the real pane (Memory → P2, Flow/Library → P3, Settings → P4, Studio → P5). |
| `MenuBarContent` — Memory & Flow sections | Phase 2 wires + un-disables the Memory items; Phase 3 wires + un-disables the Flow items and registers ⌃⌥R / ⌃⌥G. The menu-bar label gains recording status in Phase 2. |
| `Theme` | Every later phase reads its colors/type from here. |
| `Log` | Every later phase logs through it; Phase 3 adds the per-synthesis subprocess log stream. |
| `build-mengo.sh` | Phase 2 adds screenpipe-binary embedding + nested-binary signing (mirroring `build.sh`). |
| `MengoDesktopInfo.plist` | Phase 2 adds the TCC usage strings and `NSAllowsLocalNetworking`; Phase 4 adds the `mengo://` URL scheme. |
| The `pull-V1-code-just-in-time` policy | Phase 2 copies `BinaryManager.swift` / `RecorderProcess.swift` / `APIClient.swift` from `ScreenpipeMenu`; Phase 3 copies the `ScreenpipeFlow` files — each refactored for V2's app-lifecycle-tied recording and inline-pane UI. |

## Open questions for the implementation plan

- **Raising the main window from the menu**: the design uses
  `@Environment(\.openWindow) → openWindow(id: "main")` plus
  `NSApp.activate(...)`. Verify during the plan that this correctly re-creates
  the window when it has been *closed* (not just hidden); if `openWindow`
  misbehaves there, fall back to an `NSApp.windows` lookup by identifier +
  `makeKeyAndOrderFront`.
- **Final SF Symbol choices** for the five sidebar sections and the menu-bar
  label — listed above as indicative; lock them when building.
- **Whether the `AppDelegate` stays in `MengoDesktopApp.swift`** (V1 pattern,
  ~12 lines) or gets its own file once Phase 2 adds shutdown logic. Phase 1
  keeps it in-file; Phase 2 may extract it. Not a Phase 1 decision.
- **Exact accent hex / whether to ship a gradient token** — pinned in
  `Theme.swift` at implementation time from the provided icon.
