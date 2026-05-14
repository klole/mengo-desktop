# Mengo Desktop — Memory Dashboard implementation plan

**Date:** 2026-05-14
**Spec:** [`2026-05-14-mengo-memory-dashboard-design.md`](../specs/2026-05-14-mengo-memory-dashboard-design.md)
**Follows:** Phase 4 (account & licensing, wired end-to-end at `1df5dc4`).
**Branch:** `main` (small enough to land directly).

This plan turns the spec into ~22 commits across **4 parts**: A (data), B (hero + sources + activity rail), C (sessions + top apps + quick actions), D (insights + schedule + polish). Each part is independently shippable — you can stop after any part and the dashboard stays coherent (Part A alone is invisible; Part B alone replaces the hero; Part C alone adds the middle cards; Part D adds the AI cards and schedule).

The plan privileges **TDD on pure logic** (MemoryDB queries, SessionsService clustering, AppUsageService aggregation, InsightsEngine pass 1, schedule enforcement) and **manual smoke for views** (no SwiftUI snapshot infra in this repo).

## File structure overview

```
Sources/MengoDesktop/
  MemoryDB.swift                       (A1, new)
  MemoryModels.swift                   (A1, new)
  SessionsService.swift                (A2, new)
  AppUsageService.swift                (A2, new)
  ActivityFeedStream.swift             (A3, new)
  MemoryDashboardStore.swift           (A4, new — grows across parts)
  MemoryDashboardPane.swift            (B5, new)
  MemoryHero.swift                     (B2, new)
  ActivityFeedView.swift               (B4, new)
  RecentSessionsCard.swift             (C1, new)
  TopApplicationsCard.swift            (C2, new)
  QuickActionsRow.swift                (C3, new)
  MemoryListPage.swift                 (C4, new — the "View All …" page)
  InsightsCarousel.swift               (D2, new)
  Insight.swift                        (D1, new)
  InsightsEngine.swift                 (D1+D3, new)
  ScheduleRecordingSheet.swift         (D4, new)
  RecorderController.swift             (D4, modify: applySchedule)
  SettingsStore.swift                  (D1+D4, modify: aiInsightsEnabled, topAppsWindow, recordingSchedule)
  Theme.swift                          (B1, modify: orb colors + card backgrounds)
  MainWindowView.swift                 (B5, modify: swap MemoryPane → MemoryDashboardPane)
  MengoDesktopApp.swift                (A4, modify: construct store + pass through)

Tests/MengoDesktopTests/
  Fixtures/memory-db-fixture.sqlite    (A1, new)
  MemoryDBTests.swift                  (A1, new)
  SessionsServiceTests.swift           (A2, new)
  AppUsageServiceTests.swift           (A2, new)
  ActivityFeedStreamTests.swift        (A3, new)
  MemoryDashboardStoreTests.swift      (A4 + later parts, new)
  InsightsEngineTests.swift            (D1, new)
  RecorderControllerTests.swift        (D4, modify: applySchedule)
```

The old `MemoryPane.swift` stays in tree until B5 swaps it out — then it's deleted in the same commit.

## Part A — Data layer (read-only SQLite + clustering + aggregation)

### Task A1: `MemoryDB` — read-only SQLite client + fixture + model types

**Reading:** spec § "Data layer" — `MemoryDB`, `MemoryModels`.

- [ ] **Step 1: Write the failing tests** (`MemoryDBTests.swift`)
  - Build a tiny deterministic fixture DB at `Tests/MengoDesktopTests/Fixtures/memory-db-fixture.sqlite` with ~20 frames spanning Chrome / VS Code / Slack over a 30-min window, plus 6 OCR rows and 4 audio_transcriptions. Document the contents in a comment.
  - `test_topApps_today` — `topApps(window: 86400, limit: 10)` returns rows ordered desc by frame count; expected Chrome=10, VS Code=6, Slack=4; `sharePercent` sums to 100 ± 1.
  - `test_recentSessions_clustersAdjacentSameApp` — `recentSessions(limit: 10)` returns one row per contiguous same-app block (gap < 5 min); a > 5-min gap splits the block.
  - `test_recentActivity_returnsOnlyNew` — `recentActivity(since: 17, limit: 50)` returns events whose `id > 17`, newest first; calling again with the highest returned ID returns `[]`.
  - `test_lastFrameID_returnsMax` — returns the highest `id` from `frames`, or `nil` on empty DB.
- [ ] **Step 2: Run tests, expect FAIL** — `MemoryDB` doesn't exist.
- [ ] **Step 3: Implement `MemoryModels.swift`** — the plain value types listed in the spec (`AppUsageRow`, `SessionRaw`, `SessionRow`, `ActivityEvent`, `RecordingSchedule`, `TopAppsWindow`).
- [ ] **Step 4: Implement `MemoryDB.swift`** as an `actor`. Open the DB lazily on first query; close in `deinit`. Prepared statements cached per query. Bind parameters carefully (`sqlite3_bind_text` with `SQLITE_TRANSIENT`). Time-windowed queries use `strftime('%s','now') - window` against `frames.timestamp` (TEXT in screenpipe's DB — coerce via `julianday`/`strftime`).
- [ ] **Step 5: Run tests, expect PASS** — `swift test --filter MemoryDB`.
- [ ] **Step 6: Commit** — `git commit -am "MengoDesktop: MemoryDB + MemoryModels (TDD)"`.

### Task A2: `SessionsService` + `AppUsageService` — pure clustering & aggregation

- [ ] **Step 1: Write the failing tests** (`SessionsServiceTests.swift`, `AppUsageServiceTests.swift`)
  - **Sessions**:
    - `test_cluster_mergesAdjacentSameApp` — three `SessionRaw` rows all `Chrome` with end/start gaps < 5 min collapse into one `SessionRow`.
    - `test_cluster_splitsOnLargeGap` — same-app rows with a 7-min gap produce two rows.
    - `test_cluster_filtersShortSessions` — a 90-second session is filtered out (`minDuration = 120`).
    - `test_cluster_subtitleUsesDominantWindowName` — if 4 of 5 frames share `window_name = "Inbox"`, subtitle is "Inbox"; otherwise it's `"with <second app>"`.
  - **AppUsage**:
    - `test_aggregate_percentSumsTo100` — given raw counts {10, 6, 4}, `sharePercent` rounds to {50, 30, 20}.
    - `test_displayName_mapsKnownApps` — `Code` → "VS Code", `Chrome` / `Google Chrome` → "Google Chrome".
    - `test_displayName_unknownAppPassthrough` — `Cattaclysm` → "Cattaclysm" with the fallback icon.
- [ ] **Step 2: Run tests, expect FAIL**.
- [ ] **Step 3: Implement** `SessionsService.swift` + `AppUsageService.swift` (pure structs with `static func` entry points; no I/O).
- [ ] **Step 4: Run tests, expect PASS**.
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: SessionsService + AppUsageService (TDD)"`.

### Task A3: `ActivityFeedStream` — 5-second polling, diff-only emit

- [ ] **Step 1: Write the failing tests** (`ActivityFeedStreamTests.swift`)
  - Stub `MemoryDB` with a sequence of mocked diffs across three ticks (e.g. tick 1 → 3 new events, tick 2 → 0 new, tick 3 → 2 new).
  - `test_emitsOnlyNewBatches` — the stream emits exactly the non-empty batches, in order.
  - `test_failureBacksOff` — if the stub throws on tick 2, the stream waits 30 s before tick 3 (use an injectable clock).
- [ ] **Step 2: Run tests, expect FAIL**.
- [ ] **Step 3: Implement** `ActivityFeedStream.swift` — wraps an `AsyncThrowingStream` with an internal `Task` that loops `try await Task.sleep(for: interval); await db.recentActivity(since: lastID, limit: 50)`. Uses an injectable `Clock` (`ContinuousClock` in production, fake in tests).
- [ ] **Step 4: Run tests, expect PASS**.
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: ActivityFeedStream (TDD)"`.

### Task A4: `MemoryDashboardStore` — skeleton state holder

- [ ] **Step 1: Write the failing tests** (`MemoryDashboardStoreTests.swift`)
  - `test_initialState_isEmpty` — `topApps`, `recentSessions`, `recentActivity`, `insights` are all `[]`; `topAppsWindow` matches `SettingsStore` default.
  - `test_refresh_appliesStubData` — stub `MemoryDB` returns canned data; `await store.refresh()` populates `topApps` + `recentSessions`.
  - `test_setTopAppsWindow_persistsToSettings` — setting `.last7Days` writes to the injected `SettingsStore` stub.
- [ ] **Step 2: Run tests, expect FAIL**.
- [ ] **Step 3: Implement** `MemoryDashboardStore.swift` — minimal version (no activity stream consumption, no insight refresh — those land in B4 / D3). Constructor takes `recorder: RecorderController`, `db: MemoryDB`, `settings: SettingsStore`. Exposes `func refresh() async`, `var topAppsWindow: TopAppsWindow { get set }`, observable `topApps` / `recentSessions` / `recentActivity` / `insights`. `MengoDesktopApp.init()` constructs and stores it; `MainWindowView` accepts the store but doesn't render anything new yet (regression-proof — pane still shows the old `MemoryPane`).
- [ ] **Step 4: `swift build` + `swift test` — full suite green.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: MemoryDashboardStore skeleton (TDD)"`.

## Part B — Hero, inline sources, activity rail, page swap

### Task B1: Theme additions (orb + cardBackground2)

- [ ] **Step 1: Implement** — add to `Theme.swift`:
  - `Theme.orbGradient: AngularGradient` (orange center → black edge, radial; spec mockup color: `#D9740C` center, fade to `#0A0604`).
  - `Theme.orbGreen` / `.orbAmber` / `.orbRed` / `.orbGrey` — drive the recording-state pulse stroke.
  - `Theme.cardBackground2: Color` — a touch lighter than `cardBackground`; used by dashboard cards so they stack visually.
- [ ] **Step 2: `swift build` — compile.** No tests (visual-only theme tokens).
- [ ] **Step 3: Commit** — `git commit -am "MengoDesktop: Theme — orb gradient + dashboard card background"`.

### Task B2: `MemoryHero` view

- [ ] **Step 1: Implement** (`MemoryHero.swift`) — `struct MemoryHero: View { let store: MemoryDashboardStore }`. Layout:
  - Left: 88×88 `Canvas` orb (`Theme.orbGradient` + outer `Theme.orbGreen/.orbAmber/.orbRed/.orbGrey` stroke with `.symbolEffect(.pulse)` driven from the recorder state).
  - Right of orb: status word (large, `Theme.headline`) — `"Mengo is sleeping"` / `"starting…"` / `"watching"` / `"paused"` / `"hit a snag"` — plus a smaller line with the same subtitle text the old hero used.
  - Below: three rounded "pill" `Menu` buttons — Monitors (lists the entries from `recorder.lastHealth?.monitors`, each with a check mark by default-selected), Audio sources (audio devices), Capture mode (`Smart Capture` / `All changes` / `Periodic`). Each menu has a final "More options…" item that opens `RecordingSourcesView` for the advanced flow.
  - Right side: `Start Watching` primary button (toggles to "Stop") + `Schedule Recording` secondary button (opens `ScheduleRecordingSheet` once D4 lands; placeholder NSAlert until then).
- [ ] **Step 2: `swift build` — compile.**
- [ ] **Step 3: Commit** — `git commit -am "MengoDesktop: MemoryHero — orb + status + inline source pills"`.

### Task B3: `Capture mode` enum + plumbing

Capture mode is a new concept — screenpipe's recorder has knobs for it (`--vad-engine`, `--fps`, etc.) but we surface three high-level options.

- [ ] **Step 1: Write the failing tests** (extend `RecorderControllerTests`):
  - `test_setCaptureMode_smartCapture_setsFlags` — calling `setCaptureMode(.smartCapture)` writes `["--fps","1.0","--enable-frame-cache"]` (or whatever the actual flag set is — confirm against the recorder build).
  - `test_setCaptureMode_periodic_setsFlags`, `test_setCaptureMode_allChanges_setsFlags`.
- [ ] **Step 2: Implement** — add `enum CaptureMode { case smartCapture, allChanges, periodic }` + `RecorderController.setCaptureMode(_:)` that bounces the running process with the new flag set (existing `restart()` machinery does the heavy lifting). Persist last selection in `SettingsStore.captureMode`.
- [ ] **Step 3: Wire** — `MemoryHero`'s third pill toggles via `store.recorder.setCaptureMode(_:)`.
- [ ] **Step 4: Run tests, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: CaptureMode (smart / all changes / periodic) + recorder flag plumbing (TDD)"`.

### Task B4: `ActivityFeedView` + stream wiring

- [ ] **Step 1: Extend the store tests** — `test_consumesActivityStream` — wire a stub stream that emits two batches; after `await Task.yield()`, `store.recentActivity` is the concatenation (newest first, capped at 100).
- [ ] **Step 2: Run tests, expect FAIL.**
- [ ] **Step 3: Implement**:
  - In `MemoryDashboardStore`, start an activity-stream-consumer `Task` in `task()` (called from the view's `.task` modifier). Pre-pend new batches; cap at 100.
  - `ActivityFeedView.swift` — header "Recent Activity" + green dot "Live" pulse; vertical scroll of `ActivityEvent` rows. Each row: small SF Symbol by kind (`.camera`/`.waveform`/`.globe`/`.doc.text`), title, secondary line (time-ago + context). Footer link "View All Activity →" → `store.viewAllActivity(timeRange: nil)`.
- [ ] **Step 4: Run tests, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: ActivityFeedView + live stream wiring (TDD)"`.

### Task B5: `MemoryDashboardPane` + parent swap

- [ ] **Step 1: Implement** (`MemoryDashboardPane.swift`) — two-column layout:
  - Top spans full width: `MemoryHero(store:)`.
  - Below the hero: middle column (`InsightsCarousel` *placeholder* "Coming soon" card for now + `RecentSessionsCard` *placeholder* + `TopApplicationsCard` *placeholder* + `QuickActionsRow` *placeholder*) and the right rail (`ActivityFeedView(store:)`). Each placeholder is a single `Theme.card` with a small grey "Coming in part C/D" label so the page is whole at this point — no broken layout.
  - `@Environment(\.horizontalSizeClass)` / window-width gate via `GeometryReader`: below 1100 pt, the rail stacks under the middle column.
- [ ] **Step 2: Modify** `MainWindowView.swift` — `.memory` case renders `MemoryDashboardPane(store: store)` (passed in as an argument). Drop the existing `showSources` modal state — the hero owns sources now.
- [ ] **Step 3: Modify** `MengoDesktopApp.swift` — `init()` constructs `let db = MemoryDB.live()` and `let store = MemoryDashboardStore(recorder: rec, db: db, settings: st)`; pass `store` into `MainWindowView`.
- [ ] **Step 4: Delete** `MemoryPane.swift` (it's replaced by the dashboard). Update `MainWindowView`'s import list.
- [ ] **Step 5: `swift build` + `swift test` — full suite green.**
- [ ] **Step 6: Manual check** — `MENGO_DEV_ACCOUNT=pro swift run MengoDesktop`: Memory tab shows the new hero + the right-rail activity feed (live updates within ~5 s if the recorder is running); the placeholder mid-column cards are visible; nothing crashes; resizing the window crosses the 1100-pt threshold gracefully.
- [ ] **Step 7: Commit** — `git commit -am "MengoDesktop: MemoryDashboardPane + retire MemoryPane (B5)"`.

## Part C — Sessions, Top Apps, Quick Actions

### Task C1: `RecentSessionsCard`

- [ ] **Step 1: Extend the store** — add `store.recentSessions` is already there (A4); wire `refresh()` to call `MemoryDB.recentSessions(limit: 10)` → `SessionsService.cluster(_:)` → assign.
- [ ] **Step 2: Implement** (`RecentSessionsCard.swift`) — card with the "Recent Sessions" header + "View All Sessions" link (top right). Up to 3 rows of `SessionRow`. Row layout: 3 stacked app-icon avatars (`AppUsageService.iconName(for:)`) + title (`SessionRow.title`) + subtitle (duration + `frameCount` "frames" + `transcriptionCount` "words") + `Open Session` button on the right.
- [ ] **Step 3: Replace the placeholder** in `MemoryDashboardPane`.
- [ ] **Step 4: `swift build` — compile.**
- [ ] **Step 5: Manual check** — sessions render when the DB has data; "Open Session" routes (no destination yet — wire stub `print(store.openSession(id:))`).
- [ ] **Step 6: Commit** — `git commit -am "MengoDesktop: RecentSessionsCard"`.

### Task C2: `TopApplicationsCard`

- [ ] **Step 1: Extend the store** — `topAppsWindow` setter triggers a refresh; refresh queries `MemoryDB.topApps(window: window.seconds, limit: 7)` → `AppUsageService.rows(from:)`.
- [ ] **Step 2: Implement** (`TopApplicationsCard.swift`) — card header "Top Applications" + a `Picker` over `TopAppsWindow` (`.today`/`.last7Days`/`.last30Days`); horizontal bar list (`AppUsageRow.displayName` left, percent bar middle, `sharePercent` right). "View All Applications" link bottom right.
- [ ] **Step 3: Replace the placeholder.**
- [ ] **Step 4: `swift build` — compile.**
- [ ] **Step 5: Manual check** — switching the window picker updates the bars within ~ 1 s; bar widths visually match percents.
- [ ] **Step 6: Commit** — `git commit -am "MengoDesktop: TopApplicationsCard with today/7d/30d window"`.

### Task C3: `QuickActionsRow`

- [ ] **Step 1: Implement** (`QuickActionsRow.swift`) — five tiles (SF Symbol + title + caption + onTap). Targets:
  - Configure Sources → presents `RecordingSourcesView` as a sheet (re-uses existing).
  - Create Flow → `AppState.shared.selectedSection = .flow` + a one-shot `FlowController.startNewFlow()` call.
  - Train New Skill → `AppState.shared.selectedSection = .flow` (skill training is the same surface in v1).
  - Open Studio → if `account.isPro` switch to `.studio`; otherwise open `account.webURL(path: "/upgrade")` via `NSWorkspace.shared.open`.
  - Import Workflow → `NSOpenPanel` configured for `.json`; the picked URL is logged for now ("Import workflow: <url>") — full implementation lives in a Studio task (Phase 5).
- [ ] **Step 2: Replace the placeholder.**
- [ ] **Step 3: `swift build` — compile.**
- [ ] **Step 4: Commit** — `git commit -am "MengoDesktop: QuickActionsRow"`.

### Task C4: `MemoryListPage` — the View All target

Single shared list page used for "View All Activity", "View All Sessions", "View All Applications". Avoids three near-identical pages.

- [ ] **Step 1: Implement** (`MemoryListPage.swift`) — `struct MemoryListPage: View { let kind: Kind; let store: MemoryDashboardStore }` where `Kind = .activity(filter:)` / `.sessions` / `.applications`. Each kind renders a paginated long list of the corresponding store collection (no new queries — re-uses what's already loaded; "Load more" triggers `store.loadMore(_:)` which extends the in-memory cap).
- [ ] **Step 2: Route** — add an `@State private var modal: MemoryListPage.Kind?` to `MemoryDashboardPane`; the three "View All" links set it; the page renders as a full-screen `NavigationStack`-backed sheet.
- [ ] **Step 3: `swift build` — compile.**
- [ ] **Step 4: Commit** — `git commit -am "MengoDesktop: MemoryListPage (shared View All… target)"`.

## Part D — Insights, Schedule Recording, polish

### Task D1: `Insight` + `InsightsEngine` Pass 1 (heuristics only)

- [ ] **Step 1: Write the failing tests** (`InsightsEngineTests.swift`)
  - `test_detectsRepeatedAppSequence` — synthetic frames with Chrome → Slack → Notion three times → one `.workflowDetected` candidate with non-zero signal.
  - `test_detectsRepeatedFileNamePattern` — `window_name = "shopify-product.csv — VS Code"` appearing in 4 separate sessions → one `.automationOpportunity` candidate.
  - `test_focusBlock` — a single 90-min uninterrupted VS Code stretch → one `.focusPattern` candidate.
  - `test_skipsLowSignal` — a 5-min single Chrome stretch produces no candidates.
- [ ] **Step 2: Implement** `Insight.swift` (value type) + `InsightsEngine.swift` with `candidates(from frames: [Frame], over window: TimeInterval) -> [Insight]`. Deterministic templated `title` + `body` per kind. No LLM, no `SynthesisRuntime` dependency yet.
- [ ] **Step 3: Wire** — `MemoryDashboardStore.refreshInsights()` calls `InsightsEngine.candidates(...)` against the DB's last 24-h frame window; assigns to `store.insights`. Runs on the same 600-s cadence outlined in the spec.
- [ ] **Step 4: Run tests, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: InsightsEngine Pass 1 — heuristic candidates (TDD)"`.

### Task D2: `InsightsCarousel`

- [ ] **Step 1: Implement** (`InsightsCarousel.swift`) — horizontal `ScrollView` of `InsightCard`. Each card: 256-pt wide tile with kind icon + title + body + `cta` button. Prev/next chevrons paginate by visible-card width (computed from `GeometryReader`). Empty state when `store.insights.isEmpty`.
- [ ] **Step 2: Replace the placeholder in the dashboard.**
- [ ] **Step 3: Wire CTAs** — `MemoryDashboardStore.invoke(_ cta:)` switch:
  - `.createSkill(seed)` → `AppState.shared.selectedSection = .flow`; `FlowController.startNewFlow(seed: seed)`.
  - `.createFlow(seed)` → same as `.createSkill` for v1 (Flow + Skill share the surface).
  - `.viewMemory(timeRange)` → present `MemoryListPage(kind: .activity(filter: timeRange))`.
  - `.seeDetails(id)` → present a simple `InsightDetailSheet` (one-screen view of the candidate's underlying frames; render same data as MemoryListPage but pre-filtered).
- [ ] **Step 4: `swift build` — compile.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: InsightsCarousel + CTA routing"`.

### Task D3: `InsightsEngine` Pass 2 (optional LLM polish)

- [ ] **Step 1: Write the failing tests** (extend `InsightsEngineTests`)
  - `test_polish_disabled_returnsTemplatedText` — with `aiInsightsEnabled=false`, `polish(_ candidates:)` returns input unchanged.
  - `test_polish_enabled_batchesCallToRuntime` — with `aiInsightsEnabled=true` and a stub runtime returning a fixed JSON, the runtime is invoked exactly once with all candidates and the output replaces `title`/`body` on each.
  - `test_polish_runtimeFailure_fallsBackToTemplated` — stub throws; result equals input.
- [ ] **Step 2: Implement** — `InsightsEngine.polish(_ candidates: [Insight]) async -> [Insight]`. When enabled: shell out to the user's chosen `SynthesisRuntime` via `Process` (same machinery as `FlowController.synthesize`); prompt asks the model to return JSON `{"insights":[{"id":…,"title":…,"body":…}, …]}`; parse and merge. Cache the polished set on disk at `~/Library/Application Support/MengoDesktop/insights-cache.json` with `generatedAt` timestamp; `refreshInsights()` reads the cache first and only re-polishes if the cache is > 10 min old.
- [ ] **Step 3: Add `aiInsightsEnabled: Bool` to `SettingsStore`** (default `false`) + a toggle row in `SettingsPane` ("Generate insight summaries with AI — uses your Claude Code / Codex CLI; runs at most every 10 minutes").
- [ ] **Step 4: Run tests, expect PASS.**
- [ ] **Step 5: Commit** — `git commit -am "MengoDesktop: InsightsEngine Pass 2 — optional LLM polish (TDD)"`.

### Task D4: Schedule Recording

- [ ] **Step 1: Write the failing tests** (extend `RecorderControllerTests`)
  - `test_applySchedule_withinRule_resumesIfPaused` — fake clock inside a recurring rule's window; `applySchedule(_:)` calls `resumeAll()`.
  - `test_applySchedule_outsideRule_pausesIfRecording` — fake clock outside any rule; `applySchedule(_:)` calls `pauseAll()`.
  - `test_applySchedule_nilSchedule_isNoOp`.
- [ ] **Step 2: Implement** — `RecorderController.applySchedule(_ schedule: RecordingSchedule?)`. The existing health-poll task calls this each tick with `settings.recordingSchedule`. `RecordingSchedule` (in `MemoryModels.swift`) exposes `isActive(at: Date) -> Bool`.
- [ ] **Step 3: Implement** `ScheduleRecordingSheet.swift` — modal sheet with two tabs ("Recurring" / "One-off"). Recurring: weekday checkboxes + start/end `DatePicker`s; "Add rule" appends to the list. One-off: start/end `DatePicker`s. Persists to `settings.recordingSchedule`.
- [ ] **Step 4: Wire** — `MemoryHero`'s "Schedule Recording" button presents the sheet.
- [ ] **Step 5: Run tests, expect PASS.**
- [ ] **Step 6: Commit** — `git commit -am "MengoDesktop: Schedule Recording — sheet + applySchedule enforcement (TDD)"`.

### Task D5: Manual smoke checklist update

- [ ] **Step 1: Append** the "Memory Dashboard" section from the spec (the `## Manual smoke …` block) to `docs/manual-smoke-tests/mengo-phase-2-memory.md`.
- [ ] **Step 2: Commit** — `git commit -am "MengoDesktop: Memory Dashboard manual smoke checklist"`.

## Finalize

- [ ] **Full `swift build` + `swift test` — green.**
- [ ] **`./build-mengo.sh`** produces a signed bundle; launch it; walk the Memory Dashboard manual smoke checklist top-to-bottom.
- [ ] **Memory entry** — note that Memory Dashboard shipped; key facts (read-only `MemoryDB` over `~/.screenpipe/db.sqlite`, opt-in AI insights via `aiInsightsEnabled`, 10-min cache, 5-s activity feed, schedule enforcement piggy-backs on health-poll).

## Self-review checklist

- [ ] No placeholders, TBDs, or "TODO" left in the spec or plan.
- [ ] Every new file in the file-structure overview has a creating task.
- [ ] Every test file has at least one task that writes it before its implementation.
- [ ] Each task ends with a commit; commit messages follow the existing repo pattern (`MengoDesktop: <subject> (TDD)?`).
- [ ] AI usage is gated behind `aiInsightsEnabled` (opt-in), batched (one call per refresh), rate-limited (10-min cache), and falls back gracefully.
- [ ] No production code reaches outside the sandbox: `MemoryDB` only reads `~/.screenpipe/db.sqlite`; the insights cache writes to App Support; no new network calls; no new env vars required.
- [ ] Pane behaves whether the recorder is running, paused, or stopped — at most an inline notice, never a crash.
- [ ] Part A is invisible (no UI changes); Part B replaces the hero + sources + adds the rail; Part C adds the middle column; Part D adds insights + schedule. The work is independently shippable at each part boundary.
