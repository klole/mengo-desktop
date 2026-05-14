# Mengo Desktop — Memory Dashboard

**Date:** 2026-05-14
**Status:** Approved — ready for implementation plan
**Follows:** [`2026-05-12-mengo-phase-2-memory-design.md`](2026-05-12-mengo-phase-2-memory-design.md) (Memory) and the small polish in [`2026-05-12-mengo-memory-pane-redesign-design.md`](2026-05-12-mengo-memory-pane-redesign-design.md). Phase 5 (Studio) is unrelated and stays where it is.
**Goal:** Replace the bare Memory pane with the dashboard from the mockup — a glanceable, data-rich product surface that pulls 95 % of its content directly from the local recorder DB (`~/.screenpipe/db.sqlite`). Only one slice (**Mengo Insights**) ever talks to the user's Claude Code / Codex CLI, and it runs on a 10-minute cadence — not on every page render.

## What ships

```
┌─────────────────────────────────────────────────────────────────────────────────────┐
│  HERO  ──────────────────────────────────────────────────────────────────────────── │
│                                                                                     │
│  🟠 orange-pulse-orb     "Mengo is sleeping"  ·  subtitle                          │
│                                                                                     │
│   [Monitors v] [Audio sources v] [Capture mode v]  [Start Watching] [Schedule …]   │
│                                                                                     │
│  ───────────────────────────────────────────────────────────────────────────────── │
│  MENGO INSIGHTS  (carousel — 4 cards visible, prev/next chevrons)                   │
│    Workflow detected · Automation opportunity · Memory insight · Focus pattern      │
│  ───────────────────────────────────────────────────────────────────────────────── │
│  RECENT SESSIONS                  │ TOP APPLICATIONS  [Today v]                     │
│    icons · title · duration · ▶   │   Chrome ───────────────────── 45 %             │
│    icons · title · duration · ▶   │   VS Code ──────── 22 %                         │
│    icons · title · duration · ▶   │   Figma ────── 12 %                             │
│                                   │   …                                             │
│                                   │   [View All Applications]                       │
│  ───────────────────────────────────────────────────────────────────────────────── │
│  QUICK ACTIONS                                                                      │
│    [Configure Sources] [Create Flow] [Train Skill] [Open Studio] [Import Workflow]  │
└─────────────────────────────────────────────────────────────────────────────────────┘
                                                                                 ┌───┐
                                                                                 │ R │
                                                                                 │ I │
                                                                                 │ G │
                                                                                 │ H │
                                                                                 │ T │
                                                                                 │   │
                                                                                 │ R │
                                                                                 │ A │
                                                                                 │ I │
                                                                                 │ L │
                                                                                 │   │
                                                                                 │ Recent
                                                                                 │ Activity
                                                                                 │ (live,
                                                                                 │  5-s
                                                                                 │  poll)
                                                                                 └───┘
```

The right rail (Recent Activity) is fixed-width 280 pt and shows when the window is ≥ 1100 pt wide; below that, it tucks under Top Applications. The hero + middle column scale fluidly.

## Architecture

Three new layers between the existing `RecorderController` and the new `MemoryDashboardPane`. All read-only — none of this writes back to the recorder DB.

```
 ┌─ Mengo Desktop ──────────────────────────────────────────────────────────────────┐
 │                                                                                  │
 │   RecorderController (existing)  ────────────────► /health (state, monitors)     │
 │                                                                                  │
 │   MemoryDB        (read-only SQLite client over ~/.screenpipe/db.sqlite)         │
 │     ├─ topApps(window:limit:)                                                    │
 │     ├─ recentSessions(limit:)                                                    │
 │     ├─ recentActivity(since:limit:)                                              │
 │     └─ lastFrameID()                                                             │
 │                                                                                  │
 │   SessionsService (clusters frames into sessions; pure logic; testable)          │
 │   AppUsageService (aggregates frame counts per app over a time window)           │
 │   ActivityFeedStream (5-s diff polling; emits typed ActivityEvent)               │
 │   InsightsEngine (heuristic candidates + bounded LLM polish; 10-min cadence)     │
 │                                                                                  │
 │   MemoryDashboardStore                                                            │
 │      @Observable @MainActor — owns the rendered state for the pane:              │
 │        recorder (passthrough)                                                     │
 │        topApps : [AppUsageRow]                                                    │
 │        recentSessions : [SessionRow]                                              │
 │        recentActivity : [ActivityEvent]                                           │
 │        insights : [Insight]                                                       │
 │        schedule : RecordingSchedule?                                              │
 │      Refresh policies:                                                            │
 │        - on appear                                                                │
 │        - topApps + sessions on 60-s timer (cheap aggregation)                     │
 │        - activity via ActivityFeedStream (5-s diff)                               │
 │        - insights pulled from InsightsEngine cache (10-min refresh)               │
 │                                                                                  │
 │   MemoryDashboardPane (the new SwiftUI view — full rewrite of MemoryPane)         │
 │      Hero · InsightsCarousel · RecentSessions · TopApps · QuickActions · Rail    │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

## Components

### Data layer

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/MemoryDB.swift` | **new** | Tiny read-only SQLite wrapper over `~/.screenpipe/db.sqlite` using the system `SQLite3` module — no new SwiftPM dependency. Single connection per process, `actor`-isolated to serialize queries off the main thread. Public surface: `topApps(window: TimeInterval, limit: Int) async throws -> [AppUsageRow]`, `recentSessions(limit: Int) async throws -> [SessionRaw]` (raw frames-grouped-by-app-and-gap), `recentActivity(since: Int64?, limit: Int) async throws -> [ActivityEvent]`, `lastFrameID() async throws -> Int64?`, `lastAudioID() async throws -> Int64?`. Opens with `SQLITE_OPEN_READONLY` + `SQLITE_OPEN_NOMUTEX` so concurrent recorder writes are unaffected. Constructor takes a DB-URL closure (default: `~/.screenpipe/db.sqlite`) so tests can point at a temp DB. |
| `Sources/MengoDesktop/MemoryModels.swift` | **new** | Plain value types: `AppUsageRow { appName, displayName, iconName, frameCount, sharePercent }`, `SessionRaw { id, startedAt, endedAt, dominantApp, frameCount, transcriptionCount, distinctWindows }`, `SessionRow` (the displayable wrapper with humanized title + duration), `ActivityEvent` (enum: `.screenshot(at:appName:thumbnailPath:)`, `.transcription(at:snippet:)`, `.appActive(at:appName:browserURL:windowName:)`, `.urlVisited(at:url:title:)`), `RecordingSchedule { rules: [Rule] }` with `Rule = .recurring(daysOfWeek:Set<Weekday>, start:Time, end:Time) \| .oneOff(start:Date,end:Date)`. |
| `Sources/MengoDesktop/SessionsService.swift` | **new** | Pure clustering logic. `cluster(_ raws: [SessionRaw], minDuration: TimeInterval = 120, gap: TimeInterval = 300) -> [SessionRow]`. Adjacent same-app frames merge; gaps > 5 min split sessions; sessions shorter than 2 min are filtered out. Title is `<dominantAppDisplayName> session` for v1 (e.g. "Chrome session", "VS Code session"); subtitle is the single most-common `window_name` if it accounts for ≥ 40 % of frames in the session, else the second-most app name (e.g. "with Slack"). Icon stack: the top 3 app icons by frame count. Open Session jumps to that time range in the (future) Memory timeline; for v1 it just opens `View All Activity` filtered to the session's time range. |
| `Sources/MengoDesktop/AppUsageService.swift` | **new** | Pure aggregation. Given the rows from `MemoryDB.topApps`, returns an ordered list with `sharePercent` rounded for display. Maps `app_name` → human display name + SF Symbol fallback via a small built-in table (`Chrome`/`Google Chrome` → "Google Chrome" + `globe`, `Code`/`Visual Studio Code` → "VS Code" + `chevron.left.forwardslash.chevron.right`, etc.); unknown apps fall back to the raw `app_name` + `square.dashed`. |
| `Sources/MengoDesktop/ActivityFeedStream.swift` | **new** | `AsyncThrowingStream<[ActivityEvent], Error>` produced from a 5-second timer. Internally tracks `lastFrameID` + `lastAudioID`; each tick fetches the diff via `MemoryDB.recentActivity` and emits the new events newest-first. The store pre-pends them to its in-memory feed (capped at 100 items). |

### Insights (the only AI surface — strictly bounded)

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/InsightsEngine.swift` | **new** | Two-pass design. **Pass 1 (no LLM):** heuristic scan over the last 24 h of frames for candidate patterns — repeated app sequences (A → B → C three or more times today), repeated browser-URL patterns (same hostname accessed N times across X minutes), repeated file-name patterns in `window_name` (same file opened N times), focus blocks (longest contiguous single-app stretch). Each candidate has a `kind` (`.workflowDetected` / `.automationOpportunity` / `.memoryInsight` / `.focusPattern`) and a numeric `signal` score. **Pass 2 (LLM, optional):** if `SettingsStore.aiInsightsEnabled == true` *and* the user's `SynthesisRuntime` is available, take the top 4 candidates by score and ask the runtime to write a one-sentence card title + body for each in a single batched call (one CLI invocation per refresh, not per card). Cache the result on disk for 10 minutes; the pane reads from the cache. If LLM is disabled or unavailable, render the candidates with deterministic templated text ("You used Chrome → Slack → Notion 4 times today.") — the card still works, it just isn't pretty. |
| `Sources/MengoDesktop/Insight.swift` | **new** | `struct Insight { id: UUID, kind: InsightKind, title: String, body: String, cta: InsightCTA }` where `InsightCTA = .createSkill(seed:String) \| .createFlow(seed:String) \| .viewMemory(timeRange:Range<Date>) \| .seeDetails(insightID:UUID)`. Pure value type; the engine writes it, the pane reads it. |

### UI

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/MemoryDashboardPane.swift` | **new** | Full-page two-column SwiftUI view. Top: `MemoryHero`. Middle column: `InsightsCarousel`, `RecentSessionsCard`, `TopApplicationsCard`, `QuickActionsRow`. Right rail (when window ≥ 1100 pt): `ActivityFeedView`. Below the 1100-pt threshold the rail collapses and `ActivityFeedView` is rendered after `TopApplicationsCard`. Uses the existing `Theme` palette (orange = accent, ink-soft = secondary text). |
| `Sources/MengoDesktop/MemoryHero.swift` | **new** | The orb + status row + control row. The orb is a `Canvas` view that draws a radial gradient + animated pulse stroke; color reads from the recorder state (`recording` → green-orange pulse, `bothPaused` → dim grey, `error` → red). The control row is three menu-button pills (Monitors / Audio sources / Capture mode) — each opens an attached `Menu { … }` populated from `RecordingSourcesStore`'s current catalog — plus the two main buttons (Start/Stop Watching, Schedule Recording). The pills replace the modal `RecordingSourcesView` for the simple cases; the sheet is still reachable from a "More …" item in each menu for advanced settings. |
| `Sources/MengoDesktop/InsightsCarousel.swift` | **new** | Horizontal-scrolling card row with prev/next chevrons. Cards: 4 visible at lg width, 2 at md, 1 at sm. Empty state ("Connect Mengo for a few hours and we'll surface patterns you can automate.") shows when `insights.isEmpty`. Each card renders `kind` icon + `title` + `body` + `cta` button. CTA actions dispatch via `MemoryDashboardStore.invoke(_ cta:)`. |
| `Sources/MengoDesktop/RecentSessionsCard.swift` | **new** | Card with header "Recent Sessions" + "View All Sessions" link, three rows of `SessionRow` (icon stack of up to 3 app icons, title + duration, ▶ button → `MemoryDashboardStore.openSession(id:)`). |
| `Sources/MengoDesktop/TopApplicationsCard.swift` | **new** | Card with header "Top Applications" + a `Today` / `7d` / `30d` `Picker`, a list of horizontal bars (app icon · name · bar · percent), "View All Applications" link. |
| `Sources/MengoDesktop/QuickActionsRow.swift` | **new** | Five tiles laid out as a row that wraps on narrow widths. Each tile: SF Symbol + title + caption + `onTap`. Targets: Configure Sources → opens the existing `RecordingSourcesView` sheet; Create Flow → switches to the Flow tab and opens the new-flow flow; Train New Skill → switches to Flow tab too (skill training is the same surface in v1); Open Studio → switches to Studio tab (Pro-gated, redirects to /upgrade if not Pro); Import Workflow → opens a file picker for `.json` workflow files (the import format itself is a Phase 5 / Studio concern, but the picker can land here). |
| `Sources/MengoDesktop/ActivityFeedView.swift` | **new** | Right-rail vertical list. Header with "Recent Activity" + a green "Live" pulse. Up to ~ 12 visible rows of typed `ActivityEvent` (each event has a small SF Symbol per kind: `camera`/`waveform`/`globe`/`doc.text`). Subtitle line varies by event kind (transcript snippet, browser URL host, file path, etc.). "View All Activity →" footer link. |
| `Sources/MengoDesktop/MemoryDashboardStore.swift` | **new** | `@Observable @MainActor`. Owns: `var topApps`, `var recentSessions`, `var recentActivity` (capped at 100, newest-first), `var insights`, `var topAppsWindow: TopAppsWindow = .today`, plus pass-through state from `RecorderController` (orb color, status word). Refresh loop launched on `task { … }`: poll `MemoryDB.topApps` and `recentSessions` every 60 s, consume `ActivityFeedStream` continuously, request `InsightsEngine.refreshIfStale()` on a 600-s timer. Exposes `invoke(_ cta: InsightCTA)`, `openSession(id:)`, `viewAllActivity(timeRange:)`, `viewAllSessions()`, `viewAllApplications()`. |
| `Sources/MengoDesktop/ScheduleRecordingSheet.swift` | **new** | Modal sheet for one-shot + recurring schedules. Persists to `SettingsStore.recordingSchedule`. The actual *enforcement* lives in `RecorderController` — a new `applySchedule(_:)` method starts/stops the recorder according to the next rule boundary; the existing health-poll task carries the schedule check. |

### Settings + plumbing

| File | Change |
|---|---|
| `Sources/MengoDesktop/SettingsStore.swift` | Add `recordingSchedule: RecordingSchedule?` (UserDefaults-backed, JSON-encoded), `aiInsightsEnabled: Bool` (default `false` — opt-in), `topAppsWindow: TopAppsWindow` (last selection persists across launches). |
| `Sources/MengoDesktop/RecorderController.swift` | Add `applySchedule(_: RecordingSchedule?)` (no-op for `nil`). The health-poll task checks "is the current time within an active rule?" each tick; if not, calls `pauseAll()`; if yes and currently paused, calls `resumeAll()`. Pure decision; existing pause/resume machinery does the rest. |
| `Sources/MengoDesktop/Theme.swift` | Add `orbGradient` (radial orange/black), `orbGreen`, `orbRed`, `orbGrey`, and a translucent `cardBackground2` for the dashboard cards (a touch lighter than the existing `cardBackground` so cards stack visually). |
| `Sources/MengoDesktop/MainWindowView.swift` | Swap `MemoryPane(recorder:)` → `MemoryDashboardPane(store:)` for `.memory`. Drop the `showSources` modal trigger from the parent (the dashboard owns it now). |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | Construct `MemoryDB.live()` + `MemoryDashboardStore(recorder: …, db: …, settings: …, insights: …)` in `init()` and pass into `MainWindowView`. Insight engine instance lives on `MengoDesktopApp` too so it survives pane navigations. |

### Out of scope (locked)

- LLM-titled sessions (v1 uses heuristic "Chrome session" / "VS Code session" — pretty titles can ride a follow-up if `aiInsightsEnabled` proves useful).
- A real-time DB streaming layer — 5-s polling is fine for the visible UI and avoids holding the SQLite file open in a write-blocking pattern.
- The "View All Activity / Sessions / Applications" detail pages render as a single shared `MemoryListPage` with the right filter applied — but a future iteration may give each its own treatment.
- Studio integration beyond the Quick Action button (Phase 5 territory).
- Schedule Recording's notifications / lock-screen hooks (the recorder just starts/stops on schedule; nothing fancy).

## Data shapes

`mengo_users` etc. from Phase 4 are unchanged. The new on-disk JSON cache lives at `~/Library/Application Support/MengoDesktop/insights-cache.json`:

```json
{
  "generatedAt": "2026-05-14T10:30:00Z",
  "runtime": "claudeCode",
  "insights": [
    {
      "id": "…",
      "kind": "workflowDetected",
      "title": "Workflow Detected",
      "body": "You repeated the Shopify product upload process 4 times today.",
      "cta": { "type": "createSkill", "seed": "shopify-product-upload" }
    }
  ]
}
```

## Error handling

- `MemoryDB` open failures (file missing, locked) → the dashboard renders the hero + Quick Actions normally and shows a single inline notice ("Mengo is still indexing your activity — check back in a minute") in the middle column. No crash.
- `ActivityFeedStream` query failures don't stop the loop; they back off to a 30-s retry. The pane keeps the last known feed.
- `InsightsEngine` failures (CLI not found, runtime not available) silently fall back to the deterministic-template path. No alert.
- Recorder paused / not running → the dashboard still loads (topApps / sessions queries are time-windowed; an empty DB returns empty arrays).

## Testing

| Area | Coverage |
|---|---|
| `MemoryDB` | Unit-test against a fixture SQLite DB (committed to `Tests/Fixtures/memory-db-fixture.sqlite` — small, deterministic, ~20 frames). Assertions: `topApps` returns expected counts; `recentSessions` returns expected ordering; `recentActivity(since:)` returns only new events. |
| `SessionsService` | Pure-function tests: clustering on synthetic `SessionRaw` arrays — gap-splitting, min-duration filtering, dominant-app selection, subtitle heuristic. |
| `AppUsageService` | Pure tests: percent rounding, display-name mapping, unknown-app fallback. |
| `InsightsEngine` (Pass 1) | Tests on synthetic frame arrays: detects repeated app sequences, file-name patterns, focus blocks; ignores low-signal candidates. |
| `MemoryDashboardStore` | Integration-style test with stub `MemoryDB`: `invoke(.createSkill)` calls into `FlowController`; `openSession(id:)` updates `viewAllActivityFilter`; refresh loop applies new data when stub returns it. |
| `RecorderController.applySchedule` | Pure tests over a fake clock: rule transitions trigger `pauseAll` / `resumeAll` correctly. |
| Views | No SwiftUI snapshot infra — covered by an extension of the manual smoke checklist. |

## Manual smoke (new section in the existing Memory checklist)

```
## Memory Dashboard

- [ ] Hero shows the right state across recorder transitions:
      sleeping (grey orb) → starting (orange-pulse) → recording (green-pulse) →
      paused (amber) → error (red + retry).
- [ ] Each of the three pills opens a menu populated from /health monitors /
      audio_devices; toggling matches what RecordingSourcesView would do.
- [ ] Schedule Recording: add a recurring rule that starts in 1 minute, ends
      in 2 — the recorder auto-starts and auto-stops on those boundaries.
- [ ] Top Applications: bar percents add up to 100; today/7d/30d switch updates
      the data within ~2 s.
- [ ] Recent Sessions: cluster contiguous Chrome+VS Code use into one row;
      ▶ jumps to the activity feed filtered to that time range.
- [ ] Recent Activity: a new screenshot / transcription within the last 5 s
      lands at the top of the right rail with the right icon.
- [ ] Quick Actions: each tile navigates correctly; Open Studio is Pro-gated.
- [ ] Mengo Insights: with aiInsightsEnabled=false, candidate cards render
      with templated text; with true + claude/codex available, the cards
      refresh every 10 min with LLM-polished prose (check
      ~/Library/Application Support/MengoDesktop/insights-cache.json).
- [ ] Window narrower than 1100 pt: right rail collapses below Top Apps; no
      content is lost.
```

## Cost & privacy summary

- 95 % of the dashboard reads directly from the local SQLite — no network, no LLM.
- Mengo Insights is the only AI surface, and it's:
  - opt-in (`aiInsightsEnabled` defaults to `false`)
  - rate-limited (one CLI batch every 10 minutes max)
  - runs against the user's local Claude Code or Codex CLI (their tokens, their machine)
  - cached on disk so panes don't re-trigger it on every navigation

## Open questions for the implementation plan

- **DB file path** is currently locked to `~/.screenpipe/db.sqlite`. If/when the recorder folder is renamed to `~/.mengo/`, `MemoryDB.live()` follows.
- **Window-narrowing breakpoint** of 1100 pt is the proposed default; gets refined during build.
- **Schedule enforcement granularity**: the proposed health-poll-tick check (~ every 2 s) is fine for minute-resolution schedules; sub-minute rules aren't supported and the UI prevents picking them.
