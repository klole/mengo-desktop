# Mengo Desktop — Phase 2: "Mengo Memory" Design

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Playbook:** [`2026-05-12-mengo-desktop-playbook.md`](2026-05-12-mengo-desktop-playbook.md) → Phase 2
**Builds on:** [`2026-05-12-mengo-phase-1-shell-design.md`](2026-05-12-mengo-phase-1-shell-design.md) (Phase 1 — the shell, merged to `main`)
**Branch:** `mengo/phase-2-memory`

## Goal

Wire the screenpipe recorder into Mengo Desktop's lifecycle: when the user
opens the app, screenpipe spins up; when they quit, it shuts down cleanly.
Recording status, pause/resume audio, pause/resume screen, "Open data folder",
and "Open recorder log" all work from the unified menu bar dropdown. The
Memory pane in the main window shows recording status, the pause/resume
controls, the screenpipe version, lightweight session counters, and the
crash-recovery affordance. This is the first product (Mengo Memory) inside
the shell.

This is a **port-and-wire** phase: V1's `Sources/ScreenpipeMenu/` already
contains the recorder machinery (`AppState`, `RecorderProcess`, `BinaryManager`,
`APIClient`). Phase 2 re-homes those into `Sources/MengoDesktop/`, namespaced,
and connects them to the Phase 1 shell's lifecycle, menu, and main window.
V1's `ScreenpipeMenu`/`ScreenpipeFlow` source trees stay untouched.

## Decisions (locked)

| Topic | Decision | Notes |
|---|---|---|
| Recording lifecycle | Recorder starts on `applicationDidFinishLaunching`, stops on `applicationWillTerminate`. | Locked at the playbook level. Mengo Desktop has a Dock icon (`LSUIElement=false`), so closing the main window does **not** quit the app — recording continues while the app is alive in the Dock; only **Quit** stops it. |
| screenpipe binary | **Bundled** — `build-mengo.sh` downloads screenpipe at build time and embeds it in `Contents/Helpers/screenpipe` (+ `mlx.metallib`). | Required for the spawned helper to inherit Mengo Desktop's Screen Recording / Microphone TCC grants (macOS treats helpers inside a sealed `.app` as part of the parent). Matches V1's converged approach. App size grows ~150 MB. |
| Auto-update of screenpipe | **None** — ship-pinned. | The screenpipe version is whatever `build-mengo.sh` bundled; updating screenpipe means shipping a new Mengo Desktop build. Matches V1's final state (the runtime download / version-fetch code was removed). No `BinaryManager` download path. |
| Data directory | `~/.screenpipe/` (unchanged from V1; owned by the screenpipe binary). | Locked at the playbook level. "Open data folder" opens it. Recorder logs go to `~/Library/Logs/MengoDesktop/recorder.log` (renamed from V1's `ScreenpipeMenu`). The `~/.mengo/` rename is deferred. |
| State architecture | New `RecorderController` (`@Observable @MainActor`) owns the recorder lifecycle / status / pause-resume. `AppState` stays the thin nav holder. | Avoids `AppState` becoming a god object across phases. `MengoDesktopApp` owns the controller as `@State`; the `AppDelegate` keeps a weak static ref for the launch/terminate hooks (V1's bridge pattern — `ScenePhase` doesn't reliably fire on quit/logout). |
| "Pause screen" semantics | = stop the `screenpipe` process; "Resume screen" = restart it. | screenpipe exposes `/audio/start` and `/audio/stop` but no screen-pause endpoint — V1's quirk, carried forward. On resume, if audio was paused, re-issue `/audio/stop` after a short delay so the restarted recorder honours it. |
| Menu-bar label | `Mengo` text + a status-colored glyph (green = recording, yellow = paused, red = error, dotted = starting/idle). | Mirrors V1's `StatusBarLabel` semantics, but keeps the "Mengo" wordmark since this is a multi-product menu item, not a recorder-only one. |
| TCC prompt order | Request Screen Recording (`SCShareableContent.excludingDesktopWindows(...)`) + Microphone (`AVCaptureDevice.requestAccess(for:.audio)`) **before** spawning `screenpipe record`. | So macOS records the grants against Mengo Desktop; the bundled helper then inherits them. `SCShareableContent` reliably triggers the screen prompt where `CGRequestScreenCaptureAccess` is flaky. V1's approach. |

## In scope for Phase 2

- New `RecorderController` (`@Observable @MainActor`) — the Mengo Memory brain.
- Port `RecorderProcess`, `APIClient`, `BinaryManager` from V1's `ScreenpipeMenu`
  into `Sources/MengoDesktop/`, namespaced (paths → `MengoDesktop`).
- Wire screenpipe lifecycle to launch/terminate (`AppDelegate`
  `applicationDidFinishLaunching` → `recorder.start()`; `applicationWillTerminate`
  → `recorder.stop()`).
- Pause/resume audio (HTTP `/audio/stop` / `/audio/start`); pause/resume screen
  (stop/restart the process). Combined state `(audioPaused, screenPaused)`.
- Status indicator in the menu bar label (`● Recording` green / paused yellow /
  error red), mirroring V1.
- Wire the menu's "Memory" group: Pause/Resume audio, Pause/Resume screen,
  Open data folder, Open recorder log (un-disable; labels flip with state).
- The Memory pane in the main window: status line, version + data-dir line,
  pause/resume controls, "this session" counters (from `/health`),
  Open-data-folder / Open-recorder-log buttons, and (on error) a Restart
  button.
- TCC permission prompts (Screen Recording, Microphone) on first launch,
  triggered before spawning screenpipe.
- Crash recovery: if `screenpipe` exits unexpectedly, health polling fails →
  `.error`; the user clicks "Restart recorder" (menu or Memory pane) →
  `restartAfterCrash()` re-spawns it. No auto-restart loop.
- `Info.plist` additions (mic / screen-capture / camera usage strings;
  `NSAllowsLocalNetworking`).
- `build-mengo.sh` additions: build-time screenpipe download + bundle into
  `Contents/Helpers/`; sign the helper & `mlx.metallib` with the
  `ai.mengo.desktop` identifier; then sign the outer `.app`.
- `docs/manual-smoke-tests/mengo-phase-2-memory.md`.

## Explicitly NOT in Phase 2

| Deferred to | Item |
|---|---|
| Phase 2.5 | The rich "recent activity timeline" (a scrollable strip of frame thumbnails / OCR snippets queried from the screenpipe HTTP API, à la V1 `ScreenpipeFlow/TimelineWindow`). Phase 2 ships only the lightweight `/health`-derived session counters. |
| Pro / post-phase | Full vector-index memory search ("what was that staging URL I saw Tuesday?"); local vector indexing. |
| Phase 3 | Mengo Flow (skill recording / synthesis); the Flow menu group stays disabled. |
| Phase 4 | Privacy schedules (pause schedules, per-app blocklists); capture/storage/retention settings — all live in the Settings pane. Account / licensing. |
| Out of scope | Memory exports / saved search results. Renaming the data dir to `~/.mengo/`. Notarization / Mac App Store. Intel + Windows builds (the bundled helper is host-arch-specific, same as V1's `build.sh`; the Swift code stays universal). |

## Architecture

`MengoDesktop` remains a single Swift app process; Phase 2 adds the recorder
machinery and a real Memory pane, alongside the Phase 1 shell.

```
┌────────────────────────────────────────────────────────────────────┐
│  MengoDesktopApp  (@main App)                                      │
│   ├─ AppDelegate  ── applicationDidFinishLaunching → recorder.start()│
│   │                ── applicationWillTerminate     → recorder.stop() │
│   ├─ @State appState: AppState            (selectedSection — Phase 1)│
│   ├─ @State recorder: RecorderController  (NEW — Mengo Memory brain) │
│   ├─ Window "main" → MainWindowView(appState, recorder)             │
│   │      └─ detail: .memory → MemoryPane(recorder)                  │
│   │                 others  → ComingSoonPane(section)               │
│   └─ MenuBarExtra → MenuBarContent(appState, recorder)              │
│           label: "Mengo" + status glyph (from recorder.status)      │
└────────────────────────────────────────────────────────────────────┘

RecorderController (@Observable @MainActor)
   ├─ RecorderProcess   ── spawns Contents/Helpers/screenpipe record   │
   │                       (SCREENPIPE_API_KEY env, augmented PATH);   │
   │                       SIGTERM→3s→SIGKILL on stop; log →           │
   │                       ~/Library/Logs/MengoDesktop/recorder.log    │
   ├─ APIClient (actor) ── http://127.0.0.1:3030; /health,            │
   │                       /audio/start, /audio/stop; Bearer token     │
   ├─ BinaryManager     ── Bundle…/Contents/Helpers/screenpipe;        │
   │                       ensureBinary(), bundledVersion()            │
   └─ healthTask: Task  ── polls /health every 5 s; 6 fails → .error   │
```

### File layout

New / modified under `Sources/MengoDesktop/`:

| File | Action | Responsibility | Adapted from |
|---|---|---|---|
| `RecorderController.swift` | Create | `@Observable @MainActor`. Owns `RecorderProcess` + `APIClient` + the health-poll `Task`. Published: `status: RecorderStatus`, `screenpipeVersion: String?`, `session: SessionCounters`. Methods: `start()` (ensure binary → request TCC → spawn → poll), `stop()`, `pauseAudio()`/`resumeAudio()`, `pauseScreen()`/`resumeScreen()`, `restartAfterCrash()`. `dataFolderURL` (`~/.screenpipe/`), `recorderLogURL`. Registers `AppDelegate.sharedRecorder = self` in `init()`. | V1 `ScreenpipeMenu/AppState.swift` |
| `RecorderStatus.swift` | Create | `enum RecorderStatus: Equatable` — `idle`, `starting`, `recording`, `audioPaused`, `screenPaused`, `bothPaused`, `error(String)`; computed `isRecording`. Plus a free function (or `RecorderController` helper) `status(audioPaused:screenPaused:) -> RecorderStatus` mapping the four `(Bool, Bool)` combos. | V1 `ScreenpipeMenu/AppState.Status` (renamed `vision`→`screen`) |
| `RecorderProcess.swift` | Create (port) | `final class`. `start(binaryURL:)` — spawns `<binary> record` with `SCREENPIPE_API_KEY=<token>` and `PATH` prepended with `/opt/homebrew/bin:/usr/local/bin:~/.local/bin:~/bin:…` (Finder-launched apps get a minimal PATH; screenpipe needs ffmpeg); stdout/stderr → `~/Library/Logs/MengoDesktop/recorder.log` (truncated each start). `stop()` — SIGTERM, wait ≤3 s, SIGKILL. `isRunning`. `static newToken()` → `sp-<8 hex>`. | V1 `ScreenpipeMenu/RecorderProcess.swift` (paths renamed) |
| `APIClient.swift` | Create (port) | `actor`. `http://127.0.0.1:3030`, `URLSessionConfiguration.ephemeral`, 5 s timeout, `Authorization: Bearer <token>`. `health() -> HealthStatus` (`status`, `frame_status`, `audio_status`, plus any session-count fields screenpipe's `/health` exposes — decoded leniently). `audioStart()`, `audioStop()` (POST). | V1 `ScreenpipeMenu/APIClient.swift` |
| `BinaryManager.swift` | Create (port) | `enum`. `binaryURL = Bundle.main.bundleURL/Contents/Helpers/screenpipe`. `ensureBinary() throws -> URL` (executable-file check; throws `binaryNotFound`). `bundledVersion() -> String?` (runs `screenpipe --version`, parses the trailing token). No download / auto-update. | V1 `ScreenpipeMenu/BinaryManager.swift` |
| `MemoryPane.swift` | Create | `struct MemoryPane: View` — `init(recorder: RecorderController)`. Layout in the next section. The real pane for the `.memory` sidebar section. | new |
| `MengoDesktopApp.swift` | Modify | Add `@State private var recorder = RecorderController()`. Pass `recorder` to `MainWindowView` and `MenuBarContent`. The `MenuBarExtra` `label:` becomes `MenuBarLabel(status: recorder.status)`. `AppDelegate` gains `static weak var sharedRecorder: RecorderController?`, `applicationDidFinishLaunching(_:)` → `Task { await AppDelegate.sharedRecorder?.start() }` (start is async — TCC prompts + poll task), and `applicationWillTerminate(_:)` → `MainActor.assumeIsolated { AppDelegate.sharedRecorder?.stop(); Log.line("app terminating") }` (stop is sync — SIGTERM/SIGKILL, must finish before the OS reaps us). Keeps the existing `Log.bootstrap()` in `init()`. | Phase 1 file |
| `MainWindowView.swift` | Modify | `init(appState:recorder:)`. The `detail:` closure: `if appState.selectedSection == .memory { MemoryPane(recorder: recorder) } else { ComingSoonPane(section: appState.selectedSection) }`. Sidebar unchanged. | Phase 1 file |
| `MenuBarContent.swift` | Modify | `init(appState:recorder:)`. The "Memory" group: `Button` for Pause/Resume audio (`recorder.status` decides label + action), Pause/Resume screen, "Open data folder" (`NSWorkspace.shared.open(recorder.dataFolderURL)`), "Open recorder log" (`open(recorder.recorderLogURL)`); if `case .error` show "Restart recorder" → `recorder.restartAfterCrash()`. Add `struct MenuBarLabel: View` (`Text("Mengo")` + `Image(systemName:)` `.foregroundStyle(...)` by status). The "Flow" group stays `.disabled(true)`. | Phase 1 file |
| `AppState.swift` | Unchanged | Still holds only `selectedSection`. | — |

`SessionCounters` is a small `struct` (e.g. `framesCaptured: Int?`, `audioChunks: Int?`, `lastCaptureApp: String?`, `lastCaptureAt: Date?`) derived from `/health` — all optional, since screenpipe may not expose every field; the pane shows "—" for whatever's missing. (If `/health` exposes essentially nothing useful here, the pane simply shows `frame_status` / `audio_status` strings — confirmed during the plan against a real screenpipe.)

### Tests (`Tests/MengoDesktopTests/`)

- `RecorderStatusTests` — the `(audioPaused, screenPaused)` → `RecorderStatus` mapping for all four combos; `isRecording` truth table.
- `BinaryManagerTests` — `binaryURL.path` ends with `/Contents/Helpers/screenpipe`. (V1 has this exact test.)
- `RecorderProcessTests` — `newToken()` matches `^sp-[0-9a-f]{8}$`.
- `APIClientTests` — `HealthStatus` decodes correctly from captured fixture JSON (a real `/health` response); 4xx/5xx → `APIError.badStatus`; non-HTTP response → `APIError.noResponse`. (V1's `ScreenpipeClientTests` is the precedent.)
- `RecorderControllerTests` — with `RecorderProcess` and `APIClient` behind injectable protocols (or stub closures), drive: fresh controller is `.idle`; `start()` with binary present + healthy API → `.starting` → (first health OK) `.recording`; `pauseAudio()` → `.audioPaused` → `resumeAudio()` → `.recording`; `pauseScreen()` → `.screenPaused`; both → `.bothPaused`; health failures ×6 → `.error("recorder not responding")`; `restartAfterCrash()` from `.error` → `.starting`. No real `screenpipe` spawned.

(SwiftUI views — `MemoryPane`, the menu — are not unit-tested; covered by the manual smoke checklist, consistent with Phase 1.)

## UI surfaces

### Memory pane (`MemoryPane.swift`)

Replaces `ComingSoonPane(.memory)` in the detail column. Takes the
`RecorderController`; re-renders as `recorder.status` / counters change.

```
┌──────────────────────────────────────────────────────────────┐
│   ● Recording                                                │  status line — colored by status
│   screenpipe v0.3.327 · recording to ~/.screenpipe           │
│                                                              │
│   Audio    [  Pause audio  ]     Screen   [  Pause screen ]  │  labels flip Pause⇄Resume; disabled while .starting
│                                                              │
│   This session                                               │
│     Frames captured        1,284                             │  "—" if /health doesn't expose it
│     Audio chunks             312                             │
│     Last capture           Safari · 12:04:58                 │
│                                                              │
│   [ Open data folder ]    [ Open recorder log ]              │
└──────────────────────────────────────────────────────────────┘
```

- `.starting` → status line "Starting…", controls disabled.
- `.error(msg)` → status line red with `msg`; a **[ Restart recorder ]**
  button appears (→ `recorder.restartAfterCrash()`).
- `.audioPaused` / `.screenPaused` / `.bothPaused` → status line shows
  "Audio paused (screen recording)" / "Screen paused (audio recording)" /
  "Paused" (V1's `statusText` wording); the relevant button reads "Resume …".
- Counters come from the health poll; "Last capture" is best-effort (whatever
  `/health` gives — possibly just "screen: running · audio: running" if no
  finer data). No separate timeline queries in Phase 2.
- Visuals use the Phase 1 `Theme` tokens; status colors mirror `MenuBarLabel`.

### Menu bar

The dropdown's "Memory" group goes live; everything else is as Phase 1.

```
Mengo  ●                              ← MenuBarLabel: "Mengo" + status glyph
──────────────────────
Memory
  Pause audio          (⇄ Resume audio when audioPaused)
  Pause screen         (⇄ Resume screen when screenPaused)
  [ Restart recorder ]                ← only when .error
  Open data folder
  Open recorder log
Flow
  Start recording…             (disabled — Phase 3)
  Grab last 5 minutes…         (disabled — Phase 3)
──────────────────────
Library                        → main window, Library pane
Studio  (Pro)                  → main window, Studio pane
Settings…                      → main window, Settings pane
──────────────────────
Quit Mengo Desktop   ⌘Q        → terminate → applicationWillTerminate → recorder.stop()
```

`MenuBarLabel` glyph + color by `RecorderStatus`:

| Status | Glyph | Color |
|---|---|---|
| `recording` | `circle.fill` | green |
| `audioPaused` / `screenPaused` / `bothPaused` | `pause.circle.fill` | yellow |
| `error` | `exclamationmark.circle.fill` | red |
| `starting` / `idle` | `circle.dotted` | secondary |

(Same `.symbolRenderingMode(.palette)` + `.foregroundStyle(color)` trick V1
uses to get a non-template, actually-colored status item.)

## Lifecycle, TCC, crash recovery

- **Start.** `AppDelegate.applicationDidFinishLaunching` → `RecorderController.start()`:
  1. `BinaryManager.ensureBinary()` — if it throws, `status = .error("screenpipe helper missing — rebuild the app")` and stop here.
  2. Read `BinaryManager.bundledVersion()` → `screenpipeVersion`.
  3. Request TCC: `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)` (screen — reliably prompts on macOS 14+; failures are logged, not fatal); `AVCaptureDevice.requestAccess(for: .audio)` if `.notDetermined` (mic).
  4. `RecorderProcess.start(binaryURL:)` — spawn `screenpipe record`. On failure: `status = .error("failed to start recorder: …")`.
  5. `status = .starting`; begin health polling.
- **Run.** Poll `/health` every 5 s on a detached `Task`. While `.starting`, the first OK response → `.recording` (preserving any pause flags — though there are none right after start). 6 consecutive failures (~30 s) → `status = .error("recorder not responding")`, stop polling. The Dock-icon app keeps recording with no window open; only Quit stops it.
- **Pause / resume.**
  - Audio: `pauseAudio()` → `api.audioStop()` → `audioPaused = true` → recompute status. `resumeAudio()` → `api.audioStart()` → `audioPaused = false` → recompute. On HTTP failure: `status = .error("pause/resume audio failed: …")`.
  - Screen: `pauseScreen()` → cancel health poll, `recorder.stop()`, `screenPaused = true`, recompute. `resumeScreen()` → `screenPaused = false`, `ensureBinary()` + `start(binaryURL:)` + restart polling; if `audioPaused` was set, `try? await Task.sleep(.seconds(8))` then `pauseAudio()` (so the restarted recorder honours the audio-pause). On failure: `.error`.
  - `recompute`: `(audioPaused, screenPaused)` → `recording` / `audioPaused` / `screenPaused` / `bothPaused`.
- **Stop.** `applicationWillTerminate` → cancel the health task, `RecorderProcess.stop()` (SIGTERM → ≤3 s → SIGKILL), `status = .idle`. Synchronous on the main actor — small window before the OS reaps us, same as V1. Then `Log.line("app terminating")`.
- **Crash recovery.** If `screenpipe` exits unexpectedly, health polling fails → `.error`. The user clicks "Restart recorder" (menu item, only shown on `.error`, or the Memory pane button) → `restartAfterCrash()` = `recorder.stop()` (idempotent) + cancel poll + `ensureBinary()` + `start(binaryURL:)`. **No automatic restart loop** — a crash-looping recorder shouldn't silently churn battery; surface it and let the user retry.
- **Error surface.** Everything funnels into `RecorderStatus.error(String)`, which the menu-bar glyph (red), the Memory pane (red status line + Restart button), and the menu (Restart item) all reflect — one source of truth.

## Packaging

### `Resources/MengoDesktopInfo.plist` (modified)

Add to the existing Phase 1 plist:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Records microphone audio so Mengo Memory can transcribe what you say and hear. Data stays on your Mac.</string>
<key>NSScreenCaptureUsageDescription</key>
<string>Captures your screen so Mengo Memory can index what you see. Data stays on your Mac.</string>
<key>NSCameraUsageDescription</key>
<string>Required by macOS screen capture on some systems.</string>
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
</dict>
```

(`LSUIElement` stays `false`; `CFBundleIconFile`, version, etc. unchanged.)

### `build-mengo.sh` (modified)

Adapt `build.sh`'s helper-bundling steps into `build-mengo.sh` (which
currently mirrors `build-flow.sh`). After `swift build` and before assembling
the `.app`, or interleaved with assembly:

1. Detect host arch (`uname -m` → `arm64` / `x86_64` → screenpipe's `arm64` / `x64`).
2. Resolve the latest `screenpipe` version from `https://registry.npmjs.org/screenpipe/latest`.
3. Cache + download `https://registry.npmjs.org/@screenpipe/cli-darwin-<arch>/-/cli-darwin-<arch>-<version>.tgz` into `.build-cache/` (skip if already cached).
4. `mkdir -p MengoDesktop.app/Contents/Helpers`; `tar -xzf <tarball> -C …/Contents/Helpers --strip-components=2 package/bin/` (yields `screenpipe` + `mlx.metallib`); `chmod +x …/Helpers/screenpipe`.
5. Sign nested items first: `codesign --remove-signature …/Helpers/screenpipe` (best-effort); `codesign --sign <id> --force …/Helpers/mlx.metallib`; `codesign --sign <id> --force --identifier ai.mengo.desktop …/Helpers/screenpipe`; then sign the outer `.app` with `--identifier ai.mengo.desktop` (as today). The matching identifier is what makes macOS treat the helper as part of Mengo Desktop for TCC.

`<id>` = the `ScreenpipeMenu Local Dev` cert if present, else ad-hoc `-` (same logic the script already has). The `.icns` generation, plist copy, and zip steps are unchanged. The build becomes host-arch-specific for the bundled helper (V1's `build.sh` is too); the Swift binary stays universal.

`.build-cache/` is already gitignored. No new `.gitignore` entries needed.

## Testing strategy

### Swift unit tests

`RecorderStatusTests`, `BinaryManagerTests`, `RecorderProcessTests`,
`APIClientTests`, `RecorderControllerTests` — as enumerated in the
Architecture → Tests section. The controller tests use injected stubs for the
process and the HTTP client, so no real `screenpipe` runs and the tests are
deterministic. (Precedents for all of these exist in V1's `ScreenpipeMenuTests`
/ `ScreenpipeFlowTests`.)

### Manual smoke checklist — `docs/manual-smoke-tests/mengo-phase-2-memory.md`

- `swift build` / `swift test` pass (existing 51 + the new Phase 2 tests).
- `./build-mengo.sh` produces `MengoDesktop.app` with `Contents/Helpers/screenpipe` + `mlx.metallib`, both codesigned with identifier `ai.mengo.desktop`.
- Launch `MengoDesktop.app` → Screen Recording + Microphone TCC prompts appear → grant both.
- Within ~15 s the menu-bar glyph goes **green** and the Memory pane shows "● Recording" + the screenpipe version.
- `~/.screenpipe/` starts filling with data; `~/Library/Logs/MengoDesktop/recorder.log` has screenpipe output.
- Menu **Pause audio** → glyph yellow, pane shows "Audio paused"; **Resume audio** → back to green.
- Menu **Pause screen** → the `screenpipe` process exits, glyph yellow, pane shows "Screen paused"; **Resume screen** → process respawns, glyph green.
- **Open data folder** opens `~/.screenpipe/`; **Open recorder log** opens `recorder.log`.
- Kill the `screenpipe` process manually (`pkill screenpipe`) → within ~30 s the glyph goes **red**, the pane shows the error + a **Restart recorder** button; clicking it (or the menu item) brings it back to green.
- Close the main window → app stays in the Dock, glyph still green (recording continues).
- **Quit** (⌘Q or menu) → the app exits and `pgrep screenpipe` shows no orphan process; `app.log` has `app terminating`.

(The TCC-prompt and recording-actually-works items require a human at the machine — same caveat as Phase 1's visual checks.)

## Seams left for Phase 3+

| Phase 2 artifact | Picked up by |
|---|---|
| `RecorderController` (running screenpipe) | Phase 3's Mengo Flow queries the same running screenpipe via its MCP / HTTP API — no "is screenpipe running?" preflight needed (if Mengo's open, it's running). |
| `APIClient` (`/health`, `/audio/*`) | Phase 3 extends it (or adds a `ScreenpipeClient`) for Flow's timeline-thumbnail and search-content queries. |
| `MemoryPane` | Phase 2.5 slots the recent-activity timeline + the memory search box in here; Pro adds vector-index search. |
| `MenuBarContent` "Flow" group | Phase 3 un-disables + wires it (Start recording / Grab last 5 minutes), registers ⌃⌥R / ⌃⌥G. |
| `Info.plist` (TCC strings, local networking) | Phase 4 adds the `mengo://` URL scheme; privacy schedules read settings that Phase 4's Settings pane writes. |
| `RecorderController` pause/resume + privacy-relevant state | Phase 4's privacy schedules (always-paused windows, per-app blocklists) drive the same pause/resume paths on a timer / focus-change. |

## Open questions for the implementation plan

- **What `/health` actually exposes for session counts.** The Memory pane's "this session" counters depend on it. Hit a live screenpipe `/health` during the plan; if it only gives `frame_status` / `audio_status` strings, the pane shows those instead of numeric counters (and `SessionCounters` shrinks accordingly). Don't block the phase on rich counters.
- **Injectability of `RecorderProcess` / `APIClient` for `RecorderControllerTests`.** Decide during the plan: protocols (`RecorderProcessing`, `RecorderAPI`) the controller depends on, with real + stub conformers; or closure-based seams. Lean: small protocols — clean and matches how V1's testable units are shaped.
- **`@MainActor` + `@State` construction of `RecorderController`.** Same pattern Phase 1 settled (`@main @MainActor struct App`, `@State private var recorder = RecorderController()`). The controller's `init()` must be cheap (it does *not* spawn screenpipe — that's `start()`, called from `applicationDidFinishLaunching`); `init()` only wires `AppDelegate.sharedRecorder = self`.
- **Whether `applicationDidFinishLaunching` fires after the `@State` controller is constructed.** It should (the App's `@State`s are set up during scene construction, which precedes `applicationDidFinishLaunching`), so `AppDelegate.sharedRecorder` is non-nil by then. Verify during the plan; if there's a race, fall back to starting from the controller's `init()` (V1's pattern) instead.
- **Health-poll cadence / failure threshold.** V1: every 5 s, 6 fails → error. Carried forward; revisit only if it proves twitchy in the smoke test.
