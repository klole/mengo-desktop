# Mengo Desktop — Memory recording-source picker + pane polish

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Follows:** [`2026-05-12-mengo-memory-pane-redesign-design.md`](2026-05-12-mengo-memory-pane-redesign-design.md) (merged to `main` at `cdb3684`)
**Branch:** new branch off `main` at `cdb3684` (the Memory-pane-redesign work was fast-forwarded onto `main` first)

## Goal

Two things, both on the Memory pane:

1. **New feature — pick which displays and microphones to record.** screenpipe records all monitors + the default mic + system audio by default; users want to narrow that (one display only, a specific external mic, video-only, …).
2. **Polish pass** on the redesigned pane, from user feedback on the running app: the "Pause screen" button shows no icon; the "View log" link doesn't belong on this pane; the "displays" stat tile is shorter than its siblings; the blue accents (sidebar selection, link-style buttons) should be the brand orange.

Not a numbered phase — a focused follow-up to the Memory-pane redesign. No Settings pane, no per-app/window exclusions, no live (no-restart) source switching.

## What screenpipe gives us

- `screenpipe vision list -o json` → `{ "data": [ { "id": 1, "name": "Display 1", "width": 1728, "height": 1117, "is_default": true }, … ], "success": true }`. Runs whether or not the recorder is up.
- `screenpipe audio list -o json` → `{ "data": [ { "name": "MacBook Pro Microphone (input)", "is_default": false }, { "name": "System Audio (output)", "is_default": true }, … ], "success": true }`. Takes ~3–5 s (queries CoreAudio). Runs whether or not the recorder is up.
- `screenpipe record` flags (launch-time only — changing them means restarting the recorder):
  - `--monitor-id <n>` — repeatable. When passed, only those monitors are recorded (implies `--use-all-monitors=false`).
  - `--use-all-monitors` — record all (the no-`--monitor-id` default).
  - `--audio-device "<name>"` — repeatable. When passed, only those devices are recorded.
  - `--disable-audio` — no audio capture at all.
  - (no `--audio-device` and no `--disable-audio` → screenpipe's default: the default input device + system-audio output, which is what ships today.)
- A running `/health` reports `monitors` and `audio_pipeline.audio_devices` — i.e. what the *current* process was actually started with. (Both decoded already by `ScreenpipeHealth`.)

## Behaviour model

A small persisted selection drives the `record` arguments:

- **`selectedMonitorIDs: [Int]?`** — `nil` means "screenpipe default" (all monitors; pass no `--monitor-id`). A non-empty array → one `--monitor-id` per id. On launch, stored ids are intersected with the live `vision list`; if the intersection is empty (e.g. an external display is unplugged), fall back to `nil`/all so we never start with zero displays.
- **`selectedAudioDeviceNames: [String]?`** — `nil` means "screenpipe default" (default input + system audio; pass nothing). A non-empty array → one `--audio-device "name"` per device. An **explicitly empty** array (`[]`, distinct from `nil`) → pass `--disable-audio`.
- **Default / never-configured = `nil` / `nil`** → byte-for-byte today's behaviour. Untouched installs don't change.
- Persistence: `UserDefaults` (small; survives relaunch). No iCloud, no file.

Changing the selection requires restarting the recorder; the picker makes that an explicit, single action ("Apply & restart recording").

## New components

| Component | Responsibility |
|---|---|
| `Sources/MengoDesktop/SourceCatalog.swift` | `enum`/`struct` with two `async throws` methods: `availableMonitors() -> [MonitorInfo]` and `availableAudioDevices() -> [AudioDeviceInfo]`. Shells out to the bundled `screenpipe` binary (`vision list -o json` / `audio list -o json`) via `Process` off the main actor, JSON-decodes the `data` array. `MonitorInfo = (id: Int, name: String, width: Int, height: Int, isDefault: Bool)`; `AudioDeviceInfo = (name: String, isDefault: Bool, kind: .input/.output)` where `kind` is parsed from the trailing `(input)`/`(output)` in the name (and stripped from a `displayName`). Binary path comes from `BinaryManager`. |
| `Sources/MengoDesktop/RecordingSourcesStore.swift` | Thin `UserDefaults` wrapper: `var selectedMonitorIDs: [Int]?` and `var selectedAudioDeviceNames: [String]?` with the `nil` / `[]` semantics above, plus `var hasExplicitAudioSelection: Bool` (= `selectedAudioDeviceNames != nil`). Injectable `UserDefaults` for tests. |
| `Sources/MengoDesktop/RecordingSourcesView.swift` | The picker sheet (below). Takes the `RecorderController` (for the running config + the apply action) and a `SourceCatalog`. |

## Picker UI — "Recording sources" sheet (macOS System-Settings-Displays style)

Opened by a **"Configure sources…"** plain button in the Memory pane's controls row (sits with "Reveal recordings"). Presented as a **sheet** (`~520 × 460`), styled after macOS → Settings → Displays:

```
┌────────────────────────────────────────────────────────────┐
│            ┌──────────┐        ┌────────────────┐          │  top zone, lighter surface
│            │  ▭▭▭▭▭▭  │        │ ▭▭▭▭▭▭▭▭▭▭▭▭▭▭ │          │  thumbnails drawn to each monitor's
│            │  ▭▭▭▭▭▭  │ ✓      │ ▭▭▭▭▭▭▭▭▭▭▭▭▭▭ │          │  real aspect ratio; built-in = laptop
│            └──────────┘        └────────────────┘          │  silhouette, external = on a stand;
│            Built-in Display     LG SMART WQHD               │  orange ring + ✓ badge = recorded,
│            1728×1117            3440×1440                   │  dimmed/no-ring = excluded; tap toggles
│                                                            │
│                  Recording 2 of 2 displays                 │  caption; "main" tagged if isDefault
│   ────────────────────────────────────────────────────────│
│   Audio sources                                            │
│   ┌────────────────────────────────────────────────────┐  │  rounded card, hairline row separators
│   │  R-Phonak hearing aid          input        [ ●▶]  │  │  orange toggles
│   │  MacBook Pro Microphone        input        [▶○ ]  │  │
│   │  System Audio                  output       [ ●▶]  │  │
│   └────────────────────────────────────────────────────┘  │
│   No audio sources — microphone capture will be off.       │  inline note, only when all toggles off
│   ────────────────────────────────────────────────────────│
│   Changes restart recording.            [Cancel]  [Apply & restart recording]  │  footer; Apply is orange
└────────────────────────────────────────────────────────────┘
```

- **On open:** the sheet shows a centered spinner while `SourceCatalog` enumerates (the audio call is the slow one). Then the lists render.
- **Pre-selection:** seeded from what's *actually running* — `recorder.lastHealth?.monitors` and `…audio_pipeline.audio_devices` matched by id/name against the available lists. If the recorder isn't running (`.idle` / `.error`), seed from screenpipe's defaults instead: all monitors checked; the `isDefault` input device + the `(output)` "system audio" device checked.
- **Displays:** tap a thumbnail to include/exclude. The thumbnail is a small rounded rect sized to `width:height`; included = `Theme.accent` ring (≈2 pt) + a small filled-circle-checkmark badge in a corner; excluded = `opacity ~0.45`, no ring. Name below, `WIDTH×HEIGHT` caption, a tiny "Main" tag if `isDefault`. If the user tries to deselect the last remaining display, the toggle is refused (it stays on) — there's always ≥1.
- **Audio sources:** one row per device from `availableAudioDevices()` — `displayName`, a small grey `input`/`output` caption, an `Theme.accent`-tinted `Toggle` on the trailing edge. All-off is allowed and shows the inline "microphone capture will be off" note.
- **Footer:** left, the muted "Changes restart recording." line. Right, `[Cancel]` (dismiss, no changes) and `[Apply & restart recording]` — a `borderedProminent` button tinted `Theme.accent`, **enabled only when** (the chosen set ≠ what's running) **and** (≥1 display chosen). Apply: writes `selectedMonitorIDs` (`nil` if all are chosen, else the chosen ids) and `selectedAudioDeviceNames` (`nil` if the chosen set equals screenpipe's default set, `[]` if none chosen, else the chosen names) to `RecordingSourcesStore`, then calls `recorder.applyRecordingSources()`, then dismisses. The pane shows the existing `.starting` ("Starting…") state while the recorder comes back.

> "Equals screenpipe's default set" is checked so a user who opens the sheet, changes nothing, and hits Apply doesn't accidentally pin the audio devices — though in that case Apply is disabled anyway since nothing changed. Storing `nil` rather than the explicit default-set keeps "follow the system default mic" working when the user later changes their default input device.

## Changes to existing code

| File | Change |
|---|---|
| `Sources/MengoDesktop/RecorderProcess.swift` | `RecorderProcessControlling.start` gains a parameter: `func start(binaryURL: URL, extraArguments: [String]) throws`. `RecorderProcess` appends `extraArguments` after `["record"]`. (The test stub updates with the signature.) |
| `Sources/MengoDesktop/RecorderController.swift` | Inject a `RecordingSourcesStore` (default: real `UserDefaults`) and a `SourceCatalog` (default: real). Build the `record` args before each spawn: if `selectedMonitorIDs` is non-`nil`, resolve it against `await catalog.availableMonitors()` (drop ids not present; if that leaves none, ignore the selection → all); emit `--monitor-id` per surviving id. For audio: `nil` → nothing; `[]` → `--disable-audio`; non-empty → `--audio-device "name"` per name. Record what was actually passed in `runningMonitorIDs: [Int]?` / `runningAudioDeviceNames: [String]?` / `runningAudioDisabled: Bool` (for the picker's "what's running" seed and dirty-check; though the picker prefers `/health` when available). Add `func applyRecordingSources() async` — like `restartAfterCrash()` (stop process, clear pause flags, re-spawn) but reads the (already-written) store for the new args. Resolving monitors is skipped entirely when `selectedMonitorIDs == nil` (the common case → no extra subprocess on launch); if the resolve subprocess fails, log and fall back to all-monitors rather than blocking startup. |
| `Sources/MengoDesktop/MemoryPane.swift` | (1) `controls`: add a `"Configure sources…"` button (plain style, `Theme.accent` text) next to "Reveal recordings"; presents `RecordingSourcesView` as a `.sheet`. (2) Fix the "Pause screen" button's `systemImage` — `display.slash` is not a real SF Symbol (renders blank); use a valid pair (final choice verified at build time, e.g. `rectangle.slash` / `rectangle`, keeping the `mic.slash` / `mic` parallel — "show the cut-out glyph as the *action*"). (3) When `recorder.runningAudioDisabled` is true, replace the "Pause/Resume audio" button with a muted `"Microphone off — no audio sources selected"` line. (4) `footer`: drop the "View log" link entirely (it stays in the menu-bar dropdown); the privacy line becomes the whole footer. (5) `degradedBanner` copy: drop the "— open the log for details" tail (just "Screen capture is degraded." / "Microphone capture is degraded."). (6) `StatTile`: reserve two lines for every label (`lineLimit(2, reservesSpace: true)`, replacing the `.fixedSize()`) so the one-line "displays" tile is the same height as its siblings; the "displays" / "mic sources" counts now come from `recorder.runningMonitorIDs?.count` (falling back to `lastHealth?.monitors?.count`) and `runningAudioDeviceNames?.count` (falling back to the `/health` input-device count) so they reflect the actual recording configuration. |
| `Sources/MengoDesktop/MainWindowView.swift` | Make the sidebar's selected-row highlight brand orange. Try `.tint(Theme.accent)` propagation first; if macOS keeps tracking the system accent there (likely — sidebar `List` selection ignores `.tint`), switch the sidebar to manual selection: a `List` of plain rows with a custom `RoundedRectangle(Theme.accent.opacity(...))` highlight capsule behind the selected row (driven by `appState.selectedSection`), keeping keyboard navigation. |
| `Sources/MengoDesktop/Theme.swift` | No new tokens expected (`accent` / `accentHover` / `accentGlow` already exist); only if the custom sidebar highlight wants a dedicated `selectionBackground` shade. |
| `build-mengo.sh` | No change — `SourceCatalog` uses the already-bundled `Contents/Helpers/screenpipe`. |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | Add a "Recording sources" section: open the sheet → spinner → displays + mics shown, pre-checked = what's running; deselect a display, Apply, confirm recording restarts and `/health` `monitors` shows the reduced set; turn off all audio, Apply, confirm video-only (`/health` audio devices empty / audio status off) and the pane shows the "Microphone off" line; relaunch with an external display unplugged → no crash, falls back to all. Plus the polish checks: "Pause screen" has an icon; no "View log" on the pane; the four session tiles are the same height; the selected sidebar row and the in-pane links are orange, not blue. |

## Testing

Swift unit tests (no SwiftUI view tests — none in this repo; the sheet is covered by the manual checklist):

- `SourceCatalogTests` — feed canned JSON to the decode path: monitors parse (id/name/width/height/isDefault); audio devices parse and `kind` / `displayName` are derived from the `(input)` / `(output)` suffix; a missing-suffix name decodes with `kind == nil`/`.unknown`; a `success: false` or malformed body throws. (The `Process` invocation itself isn't unit-tested; the decode is split into a pure function that takes `Data`.)
- `RecordingSourcesStoreTests` — round-trip through an injected `UserDefaults(suiteName:)`: `nil` ↔ unset; `[1,2]` round-trips; `[]` round-trips and is distinct from `nil`; same for audio names.
- `RecorderControllerTests` (extend) — arg building: `selectedMonitorIDs == nil` → no `--monitor-id`, and `availableMonitors()` is *not* called; `[1,2]` with both live → `--monitor-id 1 --monitor-id 2`; `[1,9]` with only `1` live → `--monitor-id 1`; `[9]` with `9` not live → no `--monitor-id` (fallback to all); `selectedAudioDeviceNames == nil` → no audio flags; `[]` → `--disable-audio`; `["X (input)"]` → `--audio-device "X (input)"`. `applyRecordingSources()` from `.recording` with new store values → stub process restarted with the new args, `runningMonitorIDs` updated, pause flags cleared, status returns to `.starting`/`.recording`. The existing controller/process-stub tests updated for the new `start(binaryURL:extraArguments:)` signature.
- Build + `swift test` green; rebuild + re-sign the `.app`, then eyeball: the picker sheet (thumbnails, toggles, Apply enabling), Apply restarting the recorder, the "Pause screen" icon, the missing "View log", equal tile heights, orange sidebar selection + orange links.

## Out of scope

- A real Settings pane (this stays a sheet off the Memory pane).
- Per-app / per-window capture exclusions; capture region selection.
- Live source switching without a recorder restart.
- Persisting selections robustly across screenpipe upgrades that renumber monitor ids (we re-resolve each launch and fall back to all; we don't try to remember by name when ids drift).
- Audio transcription-engine / language / chunk-duration settings.
- Any Flow / Studio / account work.

## Open questions for the implementation plan

- **Sidebar orange:** confirm whether `.tint(Theme.accent)` actually colours the sidebar selection on this macOS; if not, the manual-highlight fallback is the path. Either way the answer is decided in the plan, not left open.
- **"Pause screen" symbol:** pick the exact SF Symbol pair at build time (must exist on macOS 15) — `rectangle.slash` / `rectangle` is the leading candidate; `pip.exit`-style or `eye.slash` / `eye` are alternates. Whichever, it must render and read as the same kind of "action glyph" as `mic.slash`.
- **Catalog source — CLI vs HTTP:** the spec uses the bundled-binary CLI (`vision list` / `audio list`) so the picker works when the recorder is down; the running `/health` is used only to seed "what's currently recorded". If the CLI's audio enumeration proves too slow even with the spinner, fall back to `/health` (recorder-up only) for the audio list — implementation detail.
- **Thumbnail fidelity:** generic drawn shapes (laptop silhouette for `isDefault`-ish built-in, a rect on a stand for externals), aspect-correct from `width`/`height`. No live preview, no wallpaper — out of scope; revisit only if it looks too plain.
