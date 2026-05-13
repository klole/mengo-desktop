# Mengo Desktop — Memory Pane Redesign

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Follows:** [`2026-05-12-mengo-phase-2-memory-design.md`](2026-05-12-mengo-phase-2-memory-design.md) (Phase 2 — Mengo Memory, merged to `main` at `0592e87`)
**Branch:** `mengo/memory-pane-redesign`

## Goal

Turn the Memory pane from the bare debug-screen it ships as today into a polished, information-rich product surface. Three drivers from user feedback:

1. **Bug** — the status line shows two green dots (an SF Symbol *and* a literal `●` in the text). One dot.
2. **Noise** — "Screen capture: ok / Audio capture: ok" rows are clutter when everything's fine. Surface capture health only when something's wrong.
3. **Branding & polish** — nothing user-facing may say "screenpipe" or expose `~/.screenpipe/`-style raw paths; the pane should read as "Mengo Memory", look professional, and be filled with genuinely useful at-a-glance information.

Plus a requested addition: a **"Pause both"** control alongside the existing audio / screen pause toggles.

This is a focused follow-up to Phase 2 — not a numbered phase. It does **not** add the rich activity timeline or memory search (still Phase 2.5 / Pro), and does not rename `~/.screenpipe/` (locked).

## What we have to work with

A live screenpipe `/health` exposes far more than Phase 2 currently decodes — enough to fill the pane without leaking "screenpipe": `version`, `pipeline.uptime_secs`, `pipeline.frames_captured`, `pipeline.capture_fps_actual`, `pipeline.frame_drop_rate`, `audio_pipeline.total_words`, `audio_pipeline.transcriptions_completed`, `audio_pipeline.audio_devices` (e.g. `["R-Phonak hearing aid (input)", "System Audio (output)"]`), `monitors` (e.g. `["Display 1 (1728x1117)", "Display 2 (3440x1440)"]`), `last_frame_timestamp`, `last_audio_timestamp`, `frame_status` / `audio_status`.

## The pane (target layout)

```
┌──────────────────────────────────────────────────────────────────────────┐
│                                                                          │
│   ●  Recording                                                           │  one dot (SF Symbol, soft .pulse), big
│      Capturing your screen and microphone — everything stays on this Mac.│  status word, status-colored
│      Since 1:42 PM · 4m 17s                                              │  derived from /health uptime
│                                                                          │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    Reveal         │  [Pause both] emphasized + first;
│   │  Pause both  │  │  Pause audio │  │  Pause screen│   recordings →    │  audio/screen quieter & secondary;
│   └──────────────┘  └──────────────┘  └──────────────┘                   │  "Reveal recordings" opens ~/.screenpipe
│                                                                          │  in Finder — no path text
│   ────────────────────────────────────────────────────────────────────  │
│                                                                          │
│   This session                                                           │
│     ┌──────────┐ ┌───────────┐ ┌──────────┐ ┌─────────────┐              │  StatTile: big number + small label
│     │   53     │ │   225     │ │    2     │ │      2      │               │
│     │ screens  │ │  words    │ │ displays │ │ mic sources │               │
│     │ captured │ │transcribed│ │          │ │             │               │
│     └──────────┘ └───────────┘ └──────────┘ └─────────────┘              │
│     Last capture · just now              Recordings folder · 3.2 GB      │  relative time + disk usage
│                                                                          │
│   ────────────────────────────────────────────────────────────────────  │
│   Mengo Memory keeps a private, on-device record of what you see and     │  privacy reassurance, calm grey
│   hear. Nothing is uploaded.                                View log →  │  discreet troubleshooting link
└──────────────────────────────────────────────────────────────────────────┘
```

**Visual treatment:** generous whitespace; a single typographic hierarchy (big status word → "This session" header → small grey labels); status colors carry status only (green recording / amber paused / red stopped); the app icon's orange accent stays *off* this pane (it would clash with the status semantics) — the pane is calm and monochrome-plus-status; stat tiles are rounded with a subtle elevated fill (`Theme.cardBackground`); the recording dot uses `.symbolEffect(.pulse)`; section dividers are hairlines.

**States:**

| State | Hero | Controls | "This session" |
|---|---|---|---|
| `recording` | green dot (pulsing) + "Recording" + capture subtitle + "Since … · uptime" | `[Pause both]` `[Pause audio]` `[Pause screen]` + "Reveal recordings →" | live numbers from `lastHealth` |
| `audioPaused` / `screenPaused` / `bothPaused` | amber dot + "Audio paused" / "Screen paused" / "Paused" + subtitle reflecting what's still running | "Pause both" stays "Pause both" in mixed states (pauses the rest); becomes "Resume both" in `bothPaused`; the paused axis's button reads "Resume …" | last-known numbers, slightly dimmed (when screen is paused screenpipe is down so they freeze — honest) |
| `starting` | dotted glyph + "Starting…" + small spinner | all disabled | "—" |
| `error(msg)` | red `exclamationmark.triangle.fill` + "Recorder stopped" + `msg` below | single prominent **[Restart recorder]** (replaces the pause buttons); "View log →" stays | last-known, dimmed, with "as of …" |
| health degraded (`frame_status`/`audio_status` ≠ `"ok"` while recording) | normal recording hero | an amber inline banner above the controls: "⚠ Screen capture is degraded — View log for details." | normal |

This degraded banner is the **only** place capture-status text appears — there are no "ok / ok" rows when everything's fine.

## Components & code changes

| File | Change |
|---|---|
| `Sources/MengoDesktop/APIClient.swift` | Grow `ScreenpipeHealth` to decode the fields the pane shows: `version: String?`, nested `Pipeline?` (`uptimeSecs`, `framesCaptured`), nested `AudioPipeline?` (`totalWords`, `audioDevices`), `monitors: [String]?`, `lastFrameTimestamp: String?` (kept as a raw `String?` — parsed leniently in a helper so a malformed timestamp can't fail the whole decode). All optional; the `RecorderHealthAPI.health()` signature is unchanged. `frameStatus`/`audioStatus` (already decoded) drive the "degraded" banner. |
| `Sources/MengoDesktop/RecorderController.swift` | Add `pauseAll()` (`await pauseAudio(); await pauseScreen()` — audio-stop on the live process, then kill it) and `resumeAll()` (`audioPaused = false; await resumeScreen()` — so the restarted recorder isn't re-paused). Add `recordingsSizeBytes: Int64?` — computed on a background `Task` at `start()` and refreshed on a ~60 s timer by enumerating `~/.screenpipe/` (if that's slow on huge folders, switch the enumeration to `du -sk` via `Process` — implementation detail). Add a derived `recordingSince: Date?` (from `lastHealth?.pipeline?.uptimeSecs`). No new lifecycle behaviour. |
| `Sources/MengoDesktop/MemoryPane.swift` | Full rewrite to the layout above. New private subviews: `StatTile` (number + label), a status `Hero`. New pure helpers: `relativeTime(from: Date) -> String` ("just now" / "2 minutes ago" / "3:14 PM"), `formattedBytes(_ bytes: Int64) -> String` ("3.2 GB"), `parseScreenpipeTimestamp(_ s: String) -> Date?` (tries ISO8601 with and without fractional seconds, with offset or `Z`; nil on failure). No "screenpipe", no raw paths, no engine version on this pane. |
| `Sources/MengoDesktop/Theme.swift` | Add semantic status colors `recording` (green), `paused` (amber), `stopped` (red), and `cardBackground` (a subtle elevated fill for the stat tiles). Replaces the hard-coded `.green`/`.yellow`/`.red` in the pane / menu label. |
| `Sources/MengoDesktop/MenuBarContent.swift` | Add a "Pause both" / "Resume both" item to the Memory group (sits first, before the audio/screen items). Rename "Open data folder" → "Reveal recordings", "Open recorder log" → "View log". `MenuBarLabel` uses the new `Theme` status colors. |
| `Tests/MengoDesktopTests/Fixtures/health-ok.json` | Replace with a realistic full screenpipe `/health` body (the shape observed live), so `APIClientTests` exercises the richer decode. |
| `Tests/MengoDesktopTests/APIClientTests.swift` | Add assertions that the new `ScreenpipeHealth` fields decode (frames captured, total words, monitors, audio devices, version, last-frame timestamp). |
| `Tests/MengoDesktopTests/MemoryFormattingTests.swift` (new) | Unit-test `formattedBytes` (B / KB / MB / GB boundaries), `relativeTime` ("just now" under a minute; "N minutes ago"; absolute clock time when old), `parseScreenpipeTimestamp` (parses `…-06:00`, parses `…Z`, parses `….000Z`, returns nil for garbage). |
| `Tests/MengoDesktopTests/RecorderControllerTests.swift` | Add a test that `pauseAll()` from `.recording` → `.bothPaused` (stub API records the `audioStop`; stub process records the `stop`), and `resumeAll()` from `.bothPaused` → `.recording`. |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | Update the "App behaviour" section for the new pane: one dot; no "ok" rows when healthy; "Pause both" works (→ amber "Paused", then "Resume both" → green); session stat tiles show plausible numbers; "Reveal recordings" opens Finder (no path shown anywhere); "View log" opens the log; nothing in the UI says "screenpipe". |

`RecorderController` is still `@Observable @MainActor` and still owns the recorder; `lastHealth` already updates each poll, so the pane re-renders as numbers change. The `recordingsSizeBytes` timer is a second small `Task` started in `start()` and cancelled in `stop()`, alongside the health-poll task.

## Testing

Swift unit tests as above (the pure helpers + the richer `ScreenpipeHealth` decode + `pauseAll`/`resumeAll`). The view itself isn't unit-tested (no SwiftUI snapshot infra in this repo) — covered by the updated `mengo-phase-2-memory.md` manual checklist.

## Out of scope

- The scrollable thumbnail / OCR activity timeline and memory search — Phase 2.5 / Pro.
- Renaming `~/.screenpipe/` to `~/.mengo/` — locked.
- Showing the recording-engine version anywhere — belongs in a future About/Settings pane (Phase 4), not the Memory pane.
- Any Flow / Studio / account work.

## Open questions for the implementation plan

- **`recordingsSizeBytes`**: native `FileManager` enumeration vs `du -sk` via `Process`. Lean: enumeration first (no subprocess); switch to `du` only if a large `~/.screenpipe/` makes it visibly slow. Either way it runs off the main actor and the pane shows nothing until the first result.
- **Date decoding**: keep `lastFrameTimestamp` as a `String?` on `ScreenpipeHealth` and parse it in a helper (robust — a weird value can't break the `/health` decode), rather than a `JSONDecoder` date strategy (which would fail the whole decode on an unexpected format).
- **`StatTile` count when a field is missing**: a tile whose `/health` field is absent shows "—" rather than disappearing, so the row layout stays stable across screenpipe versions.
