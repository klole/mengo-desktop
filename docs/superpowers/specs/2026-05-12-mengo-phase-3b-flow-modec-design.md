# Mengo Desktop — Phase 3b: Mengo Flow, Mode C ("Grab last N minutes")

**Date:** 2026-05-12
**Status:** Approved — ready for implementation plan
**Follows:** [`2026-05-12-mengo-phase-3a-flow-design.md`](2026-05-12-mengo-phase-3a-flow-design.md) (Phase 3a — the proactive Flow loop, merged to `main` at `e49fd66`).
**Roadmap:** [`2026-05-12-mengo-desktop-playbook.md`](2026-05-12-mengo-desktop-playbook.md) — this is the second half of Phase 3.
**V1 reference:** `Sources/ScreenpipeFlow/{ScreenpipeClient,TimelineWindow}.swift`.
**Branch:** `claude/kind-volhard-f7e189` (already off `main` at `e49fd66`).

## Goal

Add the retroactive trigger mode to Mengo Flow: the user is mid-task, realizes it's worth saving, hits **"Grab last N minutes…"** (the menu's Flow group, or the `⌃⌥G` hotkey), and a picker shows recent moments from screenpipe's buffer. They pick where the task started, hit **"Begin from here"**, and Flow enters a recording session with `mode = .retroactive` — `bufferRangeStart` set to the picked moment, `activeRecordingStart = now`. The HUD shows a buffer indicator and the "narrate forward, you can also describe what happened earlier" hint; the user continues the task while narrating (and can describe the past retrospectively). On Stop → synthesis runs as in 3a, except the `[bufferRangeStart, activeRecordingStart)` window is pre-narration: `claude` reconstructs those steps from screen + accessibility and tags them `"inferred": true` with a "verify before relying on this" note in `SKILL.md`.

## What's already shipped (3a) — nothing to redo here

- `FlowSession` already has `mode: RecordingMode` (`.proactive` / `.retroactive`) and `bufferRangeStart: Date?`, with `timeRangeStart = bufferRangeStart ?? activeRecordingStart`.
- `RecordingHUD` already shows `Buffer: Nm Ns` and the alternate hint when `session.bufferRangeStart != nil`.
- `ManifestWriter` already serializes `mode: "retroactive"` with `timeRange.start = session.timeRangeStart` (= `bufferRangeStart`) and `activeRecordingStart` separately.
- `Resources/synthesis-prompt.md` already includes step 5: for `mode == "retroactive"`, `[timeRange.start, activeRecordingStart)` is pre-narration — reconstruct from screen/accessibility, tag `inferred: true`, add a top-of-SKILL.md verify note, and align any retrospective narration with the corresponding past frames.
- `SkillFiles.parseFlowStepSummaries` already renders `inferred` steps as `"N. <intent>  (inferred — verify)"`.
- `RecorderController.screenpipeToken` is exposed (used to auth the `/search` query and already passed to `claude -p` as `SCREENPIPE_API_KEY`).

So Phase 3b is: a `/search` query, a picker UI, `FlowController.startRetroactive`, and the two entry points (menu item + `⌃⌥G`).

## Picker content (decided)

A **moment list** — what V1 actually shipped — not frame-image thumbnails. screenpipe's `GET /search?content_type=ocr` returns rows with timestamps + app names + window titles directly, so no per-frame image fetching: it's fast, simple, and the window titles tell you what was on screen. (Frame thumbnails are explicitly out of scope — a possible later polish on top of the list.)

## Components

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/ScreenpipeSearchClient.swift` | **new** | `struct Moment: Equatable, Hashable { let timestamp: Date; let appName: String; let windowName: String }`; `protocol MomentIndexing: Sendable { func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment] }`; `struct ScreenpipeSearchClient: MomentIndexing` — `init(token: String, baseURL: URL = …3030)`, hits `GET <base>/search?content_type=ocr&start_time=<iso>&end_time=<iso>&limit=<n>` with `Authorization: Bearer <token>`, returns `[Moment]` oldest-first (decimated to ≈one per 15 s). Pure `static func parseMomentIndex(_ data: Data) -> [Moment]` (decode `{data:[{type:"OCR", content:{timestamp, app_name, window_name}}]}`, tolerant ISO8601 with/without fractional seconds — reuse the lenient parse from `MemoryFormatting`/V1's `parseISO8601`) and `static func decimate(_:minIntervalSec:)`, both tested. Maps connection errors to a clear "the recorder isn't responding" message. |
| `Sources/MengoDesktop/FlowState.swift` | modify | Add `case browsingTimeline`. |
| `Sources/MengoDesktop/FlowController.swift` | modify | Inject a `MomentIndexing` (default: real `ScreenpipeSearchClient(token:)` built in `live(…)`). Add `func beginBrowsingTimeline()` (only from `.idle` → `.browsingTimeline`), `func cancelBrowsingTimeline()` (from `.browsingTimeline` → `.idle`), `func startRetroactive(bufferStart: Date) async` (preflight; on pass → `FlowSession(mode: .retroactive, bufferRangeStart: bufferStart, activeRecordingStart: now())`, `lastSession = session`, `flowState = .recording(session)`, `hudShow(session, onStop)`); `toggleRecording` also handles `.browsingTimeline → cancelBrowsingTimeline()`. Expose `func loadMoments(lookbackMinutes: Int) async throws -> [Moment]` (the picker calls this — `momentIndex(from: now - lookback, to: now, limit: 400)`), so the picker doesn't need its own client. |
| `Sources/MengoDesktop/TimelinePickerView.swift` | **new** | The SwiftUI picker, rendered by `FlowPane` for `.browsingTimeline`. State: `lookbackMinutes` (default 30), `moments: [Moment]`, `selected: Moment?`, `loading`, `loadError`. On appear (and on look-back change / `[Reload]`): `Task { moments = (try? await flow.loadMoments(lookbackMinutes:)) ?? [] }` with loading/error handling. A look-back `Picker` (15 min / 30 min / 1 h / 2 h); a `List` of moments newest-first — each row `HH:mm:ss` (mono) · **appName** · windowName (truncated), single-select; a "Selected: 2:14 PM → now (9m 42s)" caption when one's picked; footer `[Cancel] { flow.cancelBrowsingTimeline() }` / `[Begin from here] { if let m = selected { Task { await flow.startRetroactive(bufferStart: m.timestamp) } } }` (disabled until `selected != nil`). Loading → spinner; empty → "No screenpipe data in that range."; error → the message. Dark/orange, hero-styled like the other panes. Takes `let flow: FlowController`. |
| `Sources/MengoDesktop/FlowPane.swift` | modify | `case .browsingTimeline: TimelinePickerView(flow: flow)`. The idle pane's greyed `Label("Grab last N minutes… — coming soon")` becomes an active `Button("Grab last N minutes") { flow.beginBrowsingTimeline() }` (plain/orange or bordered, next to Start). The `.recording` view: when the session is `.retroactive`, also show the `Buffer: Nm Ns` line + the alternate hint (mirroring the HUD). |
| `Sources/MengoDesktop/MenuBarContent.swift` | modify | The Flow group's "Grab last 5 minutes… ⌃⌥G" item: when `.idle` → enabled, `flow.beginBrowsingTimeline()` + `reveal(.flow)`; when `.browsingTimeline` → the item shows "Cancel timeline picker" → `flow.cancelBrowsingTimeline()`; otherwise disabled. (Keep its `⌃⌥G` keyboard shortcut.) |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | modify | Register the `⌃⌥G` global hotkey: `AppDelegate.sharedHotkeys?.register(HotkeyManager.grabLast) { … }` → post a `Notification.Name.openFlowTimeline`; the menu-bar label's existing `.task` adds an observer that does `openWindow(id: "main")`, `appState.selectedSection = .flow`, `flow.beginBrowsingTimeline()`, `NSApp.activate(ignoringOtherApps: true)` — the same notification-observer pattern V1 used for "open library". |
| `Tests/MengoDesktopTests/ScreenpipeSearchClientTests.swift` | **new** | `parseMomentIndex` decodes a canned `{data:[…]}` OCR body (timestamps with and without fractional seconds; skips non-`OCR` rows; tolerates missing app/window names); `decimate` keeps ≈one row per interval; a malformed body → `[]` (or throws — pick one and test it). |
| `Tests/MengoDesktopTests/FlowControllerTests.swift` | modify | Add a `StubMoments: MomentIndexing` stub; extend `makeController` with a `moments:` param. New tests: `beginBrowsingTimeline` from `.idle` → `.browsingTimeline`; `cancelBrowsingTimeline` → `.idle`; `beginBrowsingTimeline` is a no-op when not `.idle`; `startRetroactive(bufferStart:)` → `.recording` with `mode == .retroactive` and `bufferRangeStart == bufferStart`; `startRetroactive` blocked by preflight (claude missing) stays in `.browsingTimeline` (it's called from there); `loadMoments` returns the stub's list. |
| `docs/manual-smoke-tests/mengo-phase-3b-flow-modec.md` | **new** | The Mode-C walk-through (below). |

(No new file for the HUD / ManifestWriter / synthesis prompt — they already handle retroactive.)

## Data flow

`⌃⌥G` or menu → `FlowController.beginBrowsingTimeline()` → Flow pane shows `TimelinePickerView` → it `loadMoments(lookbackMinutes:)` (→ `GET /search?content_type=ocr…` authed with the recorder token → `[Moment]` decimated) → user picks a moment → `[Begin from here]` → `FlowController.startRetroactive(bufferStart: m.timestamp)` → preflight → `FlowSession(mode: .retroactive, bufferRangeStart: m.timestamp, activeRecordingStart: now())`, `flowState = .recording` → HUD appears with `Buffer: Nm Ns` + the alternate hint → user demos forward while narrating (incl. describing the past) → Stop → `runSynthesis` → `ManifestWriter.write` emits `mode: "retroactive"`, `timeRange.start = bufferRangeStart`, `activeRecordingStart` → `claude -p` (with the existing prompt's retroactive handling) writes a skill with `inferred: true` on the pre-narration steps + a verify note → Review → Save (same as 3a).

## Error handling

- **Empty range** — `/search` returns no rows → the picker shows "No screenpipe data in that range. Try a longer look-back." `[Begin from here]` stays disabled.
- **`/search` fails** (recorder not responding, 401, network) → the picker shows the error + a `[Reload]`; doesn't crash. (If the recorder genuinely isn't running, the `.browsingTimeline` state was reached anyway — `beginBrowsingTimeline` doesn't preflight; `startRetroactive` does, so a not-running recorder is caught at "Begin from here" with the standard preflight alert.)
- **Preflight fails on "Begin from here"** — the standard preflight alert (recorder unhealthy / mic paused / claude missing / MCP not configured); the picker stays open.
- Everything downstream of `.recording` (too-short, synthesis failure, recovery on quit) is 3a's, unchanged — including: a quit mid-retroactive-recording dumps a recovery manifest with `mode: retroactive` + `bufferRangeStart`, and `synthesizeRecovery` runs `claude -p` on it (the prompt reconstructs the whole `[bufferRangeStart, quit time)` window).

## Testing

- Swift unit tests as above (`ScreenpipeSearchClientTests` + extended `FlowControllerTests`). No SwiftUI view tests (none in this repo) — the picker is covered by the manual checklist.
- Build + `swift test` green; rebuild the `.app` (`./build-mengo.sh`), relaunch, eyeball the picker.
- **Manual smoke checklist** `docs/manual-smoke-tests/mengo-phase-3b-flow-modec.md`:
  - Do something for a couple of minutes, then **menu → "Grab last 5 minutes…"** (or `⌃⌥G`): the Flow pane shows the picker; within a moment it lists recent moments (`HH:mm:ss · app · window title`), newest first; the look-back picker re-queries.
  - Pick a moment → the "Selected: … → now (Nm Ns)" caption appears → **Begin from here** → the picker closes; a recording HUD appears showing `● Recording 0:NN  Buffer: Nm Ns` and the "Narrate forward; you can also describe what happened earlier." hint.
  - Continue the task while narrating, and also narrate something about the *earlier* (pre-pick) part. Stop → synthesis → in the **Review**, the SKILL.md preview has a top note flagging some steps for verification, and the step list shows the early ones as "(inferred — verify)".
  - Save → it's in the Library; invoke it via `claude` — confirm the intent works.
  - From the picker, **Cancel** → back to the Flow idle pane.
  - With a look-back range that has no screenpipe data → "No screenpipe data in that range."
  - Start a Mode-C recording, then **quit the app** mid-recording → relaunch → "An earlier recording was interrupted — synthesize it?" → yes → it synthesizes the whole grabbed window.

## Out of scope (Phase 3b)

Frame-image thumbnails in the picker (the moment list is the picker for now); audio scrub-preview at the selected moment; a "preview the OCR/transcript at this moment" hover. (Phase 4 = account/licensing; Phase 5 = Studio.)

## Open questions for the implementation plan

- **`/search` response shape** — confirm against a live screenpipe that `GET /search?content_type=ocr` still returns `{data:[{type:"OCR", content:{timestamp, app_name, window_name}}]}` (V1's parser assumes this; screenpipe's API may have drifted). If `type` is lower-case `"ocr"` or the keys differ, adjust `parseMomentIndex` — keep the decode tolerant (skip rows that don't match rather than failing the whole parse).
- **ISO8601 leniency** — reuse the existing tolerant parser (`MemoryFormatting.parseTimestamp` from Phase 2, or V1's `ScreenpipeClient.parseISO8601`) rather than adding a third; pick one in the plan.
- **`⌃⌥G` window-raise plumbing** — `openWindow` isn't available outside a `View`; the plan uses the `NotificationCenter` + menu-bar-label-`.task`-observer pattern V1 used for "open library". Confirm that still works with the current `MenuBarExtra` setup; if not, fall back to `NSApp.activate` + relying on the window already being open.
