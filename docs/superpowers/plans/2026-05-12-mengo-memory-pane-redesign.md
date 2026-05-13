# Mengo Desktop — Memory Pane Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bare debug-screen Memory pane with a polished product surface — one status dot, capture-health text only when degraded, no "screenpipe" or raw paths in the UI, a status hero + "this session" stat tiles + recordings disk usage + privacy line + discreet log link — and add a "Pause both" / "Resume both" control.

**Architecture:** Extend `ScreenpipeHealth` to decode the richer `/health` fields; add `RecorderController.pauseAll()`/`resumeAll()` (thin compositions) plus a view-triggered recordings-folder size; add semantic `Theme` status colors; rewrite `MemoryPane` against those; tweak the menu bar's Memory group. Pure formatting/parsing helpers live in a small `MemoryFormatting` enum so they're unit-testable.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, SwiftPM, XCTest.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-memory-pane-redesign-design.md`](../specs/2026-05-12-mengo-memory-pane-redesign-design.md)

**Working directory for every command below:** `/Users/your-user/screenpipe/.claude/worktrees/mengo-phase-1-shell` (the dir containing `Package.swift`; it holds the `mengo/memory-pane-redesign` branch).

---

## File Structure

| File | Change |
|---|---|
| `Sources/MengoDesktop/MemoryFormatting.swift` | **Create** — `enum MemoryFormatting` with pure helpers: `bytes(_:)` ("3.2 GB"), `relative(from:)` ("just now" / "2 minutes ago" / "3:14 PM"), `duration(seconds:)` ("4m 17s" / "2h 14m"), `parseTimestamp(_:)` (lenient ISO8601 → `Date?`). |
| `Sources/MengoDesktop/APIClient.swift` | **Modify** — grow `ScreenpipeHealth`: add `version: String?`, `pipeline: Pipeline?`, `audioPipeline: AudioPipeline?`, `monitors: [String]?`, `lastFrameTimestamp: String?` (all optional, `= nil` defaults). Add nested `struct Pipeline { uptimeSecs: Double?; framesCaptured: Int? }` and `struct AudioPipeline { totalWords: Int?; audioDevices: [String]? }`. |
| `Sources/MengoDesktop/Theme.swift` | **Modify** — add `static let recording = Color.green`, `paused` (amber), `stopped = Color.red`, `cardBackground` (subtle elevated fill). |
| `Sources/MengoDesktop/RecorderController.swift` | **Modify** — add `pauseAll()` / `resumeAll()`; `private(set) var recordingsSizeBytes: Int64?` + `func refreshRecordingsSize() async` (walks `~/.screenpipe/`, off the main actor); computed `var recordingSince: Date?` (from `lastHealth?.pipeline?.uptimeSecs`). |
| `Sources/MengoDesktop/MemoryPane.swift` | **Rewrite** — the polished layout (hero / degraded banner / controls / "this session" tiles / footer), a private `StatTile`, a `.task` that refreshes the recordings size while visible. |
| `Sources/MengoDesktop/MenuBarContent.swift` | **Modify** — add "Pause both" / "Resume both" to the Memory group (first); rename "Open data folder" → "Reveal recordings", "Open recorder log" → "View log"; `MenuBarLabel` uses the new `Theme` colors. |
| `Tests/MengoDesktopTests/MemoryFormattingTests.swift` | **Create** — `bytes`, `relative`, `duration`, `parseTimestamp`. |
| `Tests/MengoDesktopTests/Fixtures/health-ok.json` | **Replace** — a realistic full screenpipe `/health` body. |
| `Tests/MengoDesktopTests/APIClientTests.swift` | **Modify** — assert the new `ScreenpipeHealth` fields decode. |
| `Tests/MengoDesktopTests/RecorderControllerTests.swift` | **Modify** — add `pauseAll` → `.bothPaused` and `resumeAll` → `.recording` tests. |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | **Modify** — update the "App behaviour" section for the new pane. |

---

## Task 1: `MemoryFormatting` helpers (TDD)

**Files:**
- Create: `Sources/MengoDesktop/MemoryFormatting.swift`
- Create: `Tests/MengoDesktopTests/MemoryFormattingTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MengoDesktopTests/MemoryFormattingTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class MemoryFormattingTests: XCTestCase {

    func test_bytes_scalesWithMagnitude() {
        XCTAssertFalse(MemoryFormatting.bytes(0).isEmpty)
        XCTAssertTrue(MemoryFormatting.bytes(1_500).contains("KB"))
        XCTAssertTrue(MemoryFormatting.bytes(5_000_000).contains("MB"))
        XCTAssertTrue(MemoryFormatting.bytes(3_200_000_000).contains("GB"))
    }

    func test_duration_abbreviates() {
        XCTAssertEqual(MemoryFormatting.duration(seconds: 0), "0s")
        XCTAssertEqual(MemoryFormatting.duration(seconds: 5), "5s")
        XCTAssertEqual(MemoryFormatting.duration(seconds: 257), "4m 17s")
        XCTAssertEqual(MemoryFormatting.duration(seconds: 8040), "2h 14m")
    }

    func test_relative_recentIsJustNow_olderCountsMinutes() {
        let now = Date()
        XCTAssertEqual(MemoryFormatting.relative(from: now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(MemoryFormatting.relative(from: now.addingTimeInterval(-120), now: now), "2 minutes ago")
        XCTAssertEqual(MemoryFormatting.relative(from: now.addingTimeInterval(-60), now: now), "1 minute ago")
    }

    func test_relative_oldFallsBackToClockTime() {
        let now = Date()
        let old = now.addingTimeInterval(-3 * 3600)   // 3 h ago
        let s = MemoryFormatting.relative(from: old, now: now)
        XCTAssertFalse(s.contains("ago"))             // a clock time like "3:14 PM", not "3 hours ago"
        XCTAssertFalse(s.isEmpty)
    }

    func test_parseTimestamp_handlesOffsetAndZAndFractional_andRejectsGarbage() {
        XCTAssertNotNil(MemoryFormatting.parseTimestamp("2026-05-12T18:31:18-06:00"))
        XCTAssertNotNil(MemoryFormatting.parseTimestamp("2026-05-12T19:04:58Z"))
        XCTAssertNotNil(MemoryFormatting.parseTimestamp("2026-05-12T19:04:58.000Z"))
        XCTAssertNil(MemoryFormatting.parseTimestamp("not a date"))
        XCTAssertNil(MemoryFormatting.parseTimestamp(""))
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run: `swift test --filter MemoryFormattingTests`
Expected: FAIL — "cannot find 'MemoryFormatting' in scope".

- [ ] **Step 3: Create `MemoryFormatting.swift`**

Create `Sources/MengoDesktop/MemoryFormatting.swift`:

```swift
import Foundation

/// Pure formatting/parsing helpers for the Memory pane. No UI, no I/O.
enum MemoryFormatting {

    /// e.g. "3.2 GB". Uses the OS file-size formatter.
    static func bytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: count)
    }

    /// e.g. "4m 17s", "2h 14m", "0s". Two largest non-zero units.
    static func duration(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// "just now" (< 60 s), "N minute(s) ago" (< 60 min), else a short clock time ("3:14 PM").
    static func relative(from date: Date, now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 {
            let mins = Int(delta / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s") ago"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Parse a screenpipe timestamp string leniently. Returns nil rather than throwing,
    /// so a malformed value never breaks a `/health` decode that carries it elsewhere.
    static func parseTimestamp(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `swift test --filter MemoryFormattingTests`
Expected: PASS — 5 tests, 0 failures.

- [ ] **Step 5: Build + commit**

Run: `swift build --product MengoDesktop` → `Build complete!`

```bash
git add Sources/MengoDesktop/MemoryFormatting.swift Tests/MengoDesktopTests/MemoryFormattingTests.swift
git commit -m "MengoDesktop: MemoryFormatting — bytes / duration / relative-time / timestamp-parse helpers (TDD)"
```

---

## Task 2: Extend `ScreenpipeHealth` to decode the richer `/health`

**Files:**
- Modify: `Sources/MengoDesktop/APIClient.swift`
- Modify: `Tests/MengoDesktopTests/Fixtures/health-ok.json`
- Modify: `Tests/MengoDesktopTests/APIClientTests.swift`

- [ ] **Step 1: Replace the fixture with a realistic full body**

Replace `Tests/MengoDesktopTests/Fixtures/health-ok.json` with:

```json
{
  "status": "healthy",
  "frame_status": "ok",
  "audio_status": "ok",
  "version": "0.3.327",
  "message": "all systems are functioning normally.",
  "last_frame_timestamp": "2026-05-12T18:31:18-06:00",
  "last_audio_timestamp": "2026-05-12T18:31:18-06:00",
  "monitors": ["Display 1 (1728x1117)", "Display 2 (3440x1440)"],
  "pipeline": {
    "uptime_secs": 257.135986583,
    "frames_captured": 53,
    "frames_db_written": 53,
    "capture_fps_actual": 0.206,
    "frame_drop_rate": 0.0
  },
  "audio_pipeline": {
    "uptime_secs": 257.135988833,
    "total_words": 225,
    "transcriptions_completed": 16,
    "audio_devices": ["R-Phonak hearing aid (input)", "System Audio (output)"]
  }
}
```

- [ ] **Step 2: Add the failing test assertions**

In `Tests/MengoDesktopTests/APIClientTests.swift`, replace `test_screenpipeHealth_decodesCoreFields_ignoringExtras` with:

```swift
    func test_screenpipeHealth_decodesCoreAndRichFields() throws {
        let data = try loadFixture("health-ok.json")
        let h = try JSONDecoder().decode(ScreenpipeHealth.self, from: data)
        XCTAssertEqual(h.status, "healthy")
        XCTAssertEqual(h.frameStatus, "ok")
        XCTAssertEqual(h.audioStatus, "ok")
        XCTAssertEqual(h.version, "0.3.327")
        XCTAssertEqual(h.monitors, ["Display 1 (1728x1117)", "Display 2 (3440x1440)"])
        XCTAssertEqual(h.pipeline?.framesCaptured, 53)
        XCTAssertEqual(h.pipeline?.uptimeSecs.map { Int($0) }, 257)
        XCTAssertEqual(h.audioPipeline?.totalWords, 225)
        XCTAssertEqual(h.audioPipeline?.audioDevices, ["R-Phonak hearing aid (input)", "System Audio (output)"])
        XCTAssertEqual(h.lastFrameTimestamp, "2026-05-12T18:31:18-06:00")
    }
```

(Keep `test_screenpipeHealth_decodesFromMinimalBody` and `test_apiClient_baseURLIsLocalScreenpipe` as they are.)

- [ ] **Step 3: Run — expect compile failure**

Run: `swift test --filter APIClientTests`
Expected: FAIL — `ScreenpipeHealth` has no `version` / `monitors` / `pipeline` / `audioPipeline` / `lastFrameTimestamp`.

- [ ] **Step 4: Extend `ScreenpipeHealth` in `APIClient.swift`**

In `Sources/MengoDesktop/APIClient.swift`, replace the `ScreenpipeHealth` struct with:

```swift
/// screenpipe's `/health` response — the subset Mengo Memory surfaces. screenpipe
/// includes more; unknown keys are ignored, and any field a build omits is `nil`.
/// `lastFrameTimestamp` is kept as a raw string and parsed leniently by the UI so a
/// malformed value can't fail the whole decode.
struct ScreenpipeHealth: Decodable, Sendable {
    var status: String
    var frameStatus: String
    var audioStatus: String
    var version: String? = nil
    var monitors: [String]? = nil
    var lastFrameTimestamp: String? = nil
    var pipeline: Pipeline? = nil
    var audioPipeline: AudioPipeline? = nil

    struct Pipeline: Decodable, Sendable {
        var uptimeSecs: Double? = nil
        var framesCaptured: Int? = nil
        private enum CodingKeys: String, CodingKey {
            case uptimeSecs = "uptime_secs"
            case framesCaptured = "frames_captured"
        }
    }

    struct AudioPipeline: Decodable, Sendable {
        var totalWords: Int? = nil
        var audioDevices: [String]? = nil
        private enum CodingKeys: String, CodingKey {
            case totalWords = "total_words"
            case audioDevices = "audio_devices"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case status, version, monitors, pipeline
        case frameStatus = "frame_status"
        case audioStatus = "audio_status"
        case lastFrameTimestamp = "last_frame_timestamp"
        case audioPipeline = "audio_pipeline"
    }
}
```

- [ ] **Step 5: Run — expect PASS**

Run: `swift test --filter APIClientTests`
Expected: PASS. Then `swift test` — full suite green (the `StubAPI` in `RecorderControllerTests` still constructs `ScreenpipeHealth(status:frameStatus:audioStatus:)` since the new fields default to `nil`; `MemoryPane`'s current code still reads `.frameStatus`/`.audioStatus`).

- [ ] **Step 6: Build + commit**

```bash
git add Sources/MengoDesktop/APIClient.swift Tests/MengoDesktopTests/APIClientTests.swift Tests/MengoDesktopTests/Fixtures/health-ok.json
git commit -m "MengoDesktop: ScreenpipeHealth decodes the richer /health (version, monitors, pipeline, audio_pipeline, last_frame_timestamp)"
```

---

## Task 3: `Theme` — semantic status colors + card background

**Files:**
- Modify: `Sources/MengoDesktop/Theme.swift`

- [ ] **Step 1: Add the tokens**

In `Sources/MengoDesktop/Theme.swift`, inside `enum Theme`, after the existing colour block, add:

```swift
    // MARK: - Status & surfaces

    /// Recorder is healthy and running.
    static let recording = Color.green
    /// Recorder is paused (audio, screen, or both).
    static let paused = Color(red: 0.92, green: 0.62, blue: 0.10)   // a calmer amber than .yellow
    /// Recorder stopped / errored.
    static let stopped = Color.red
    /// Subtle elevated fill for cards/tiles within a pane.
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
```

- [ ] **Step 2: Build + commit**

Run: `swift build --product MengoDesktop` → `Build complete!`

```bash
git add Sources/MengoDesktop/Theme.swift
git commit -m "MengoDesktop: Theme — semantic recording/paused/stopped colors + cardBackground"
```

---

## Task 4: `RecorderController` — Pause-both, recordings size, derived "since"

**Files:**
- Modify: `Sources/MengoDesktop/RecorderController.swift`
- Modify: `Tests/MengoDesktopTests/RecorderControllerTests.swift`

- [ ] **Step 1: Add the `pauseAll` / `resumeAll` tests**

In `Tests/MengoDesktopTests/RecorderControllerTests.swift`, add to the `// MARK: Tests` section:

```swift
    func test_pauseAll_thenResumeAll() async {
        let api = StubAPI()
        let proc = StubProcess()
        let c = makeController(process: proc, api: api)
        await c.start()
        await eventually { c.status == .recording }
        await c.pauseAll()
        XCTAssertEqual(c.status, .bothPaused)
        let stops = await api.audioStopCount
        XCTAssertEqual(stops, 1)
        XCTAssertEqual(proc.stopCount, 1)
        let startsBefore = proc.startCount
        await c.resumeAll()
        await eventually { c.status == .recording }
        XCTAssertEqual(proc.startCount, startsBefore + 1)
        // resumeAll cleared the audio-paused flag, so the restarted recorder isn't re-paused.
        let stopsAfter = await api.audioStopCount
        XCTAssertEqual(stopsAfter, 1)
    }
```

- [ ] **Step 2: Run — expect compile failure**

Run: `swift test --filter RecorderControllerTests`
Expected: FAIL — `RecorderController` has no `pauseAll` / `resumeAll`.

- [ ] **Step 3: Add the methods + recordings size + derived `recordingSince` to `RecorderController.swift`**

In `Sources/MengoDesktop/RecorderController.swift`:

(a) Add a published property near `lastHealth`:

```swift
    private(set) var recordingsSizeBytes: Int64?
```

(b) Add to the `// MARK: - Pause / resume` section (after `resumeScreen()`):

```swift
    func pauseAll() async {
        await pauseAudio()      // stop audio on the still-live process…
        await pauseScreen()     // …then kill the process
    }

    func resumeAll() async {
        audioPaused = false     // clear first so resumeScreen() doesn't re-pause audio
        await resumeScreen()
    }
```

(c) Add a computed property near `dataFolderURL`:

```swift
    /// When the current recording session started, derived from screenpipe's reported uptime.
    var recordingSince: Date? {
        guard status == .recording, let up = lastHealth?.pipeline?.uptimeSecs else { return nil }
        return Date().addingTimeInterval(-up)
    }
```

(d) Add a `// MARK: - Recordings size` section before `// MARK: - TCC`:

```swift
    /// Recompute the total size of `~/.screenpipe/` off the main actor. Cheap for typical
    /// folders; the Memory pane calls this when it appears and every ~60 s while visible.
    func refreshRecordingsSize() async {
        let dir = dataFolderURL
        let size = await Task.detached(priority: .utility) { () -> Int64? in
            guard let en = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]) else { return nil }
            var total: Int64 = 0
            for case let url as URL in en {
                guard let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                      vals.isRegularFile == true else { continue }
                total += Int64(vals.totalFileAllocatedSize ?? 0)
            }
            return total
        }.value
        if let size { recordingsSizeBytes = size }
    }
```

- [ ] **Step 4: Run — expect PASS**

Run: `swift test --filter RecorderControllerTests`
Expected: PASS — the new test plus all existing controller tests. Then `swift test` — full suite green.

- [ ] **Step 5: Build + commit**

Run: `swift build --product MengoDesktop` → `Build complete!`

```bash
git add Sources/MengoDesktop/RecorderController.swift Tests/MengoDesktopTests/RecorderControllerTests.swift
git commit -m "MengoDesktop: RecorderController — pauseAll/resumeAll, recordings-folder size, derived recordingSince"
```

---

## Task 5: Rewrite `MemoryPane`

**Files:**
- Rewrite: `Sources/MengoDesktop/MemoryPane.swift`

(No unit test — SwiftUI view; verified visually in the smoke checklist.)

- [ ] **Step 1: Replace `MemoryPane.swift`**

Overwrite `Sources/MengoDesktop/MemoryPane.swift`:

```swift
import SwiftUI

/// The Memory product's pane — an at-a-glance view of the on-device recorder.
/// No "screenpipe" branding, no raw paths, no engine version: this is "Mengo Memory".
struct MemoryPane: View {
    let recorder: RecorderController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let msg = degradedMessage { degradedBanner(msg) }
                controls
                Divider()
                sessionSection
                Divider()
                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paneBackground)
        .task {
            while !Task.isCancelled {
                await recorder.refreshRecordingsSize()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder private var hero: some View {
        HStack(alignment: .top, spacing: 11) {
            heroDot.padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle).font(Theme.title).foregroundStyle(heroColor)
                if let subtitle = heroSubtitle {
                    Text(subtitle).font(Theme.body).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = heroDetail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var heroDot: some View {
        switch recorder.status {
        case .recording:
            Image(systemName: "circle.fill").font(.system(size: 12))
                .foregroundStyle(Theme.recording).symbolEffect(.pulse)
        case .audioPaused, .screenPaused, .bothPaused:
            Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(Theme.paused)
        case .starting:
            ProgressView().controlSize(.small)
        case .idle:
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.stopped)
        }
    }

    private var heroColor: Color {
        switch recorder.status {
        case .recording: return Theme.recording
        case .audioPaused, .screenPaused, .bothPaused: return Theme.paused
        case .error: return Theme.stopped
        case .starting, .idle: return Theme.primaryText
        }
    }

    private var heroTitle: String {
        switch recorder.status {
        case .idle: return "Not recording"
        case .starting: return "Starting…"
        case .recording: return "Recording"
        case .audioPaused: return "Audio paused"
        case .screenPaused: return "Screen paused"
        case .bothPaused: return "Paused"
        case .error: return "Recorder stopped"
        }
    }

    private var heroSubtitle: String? {
        switch recorder.status {
        case .recording:    return "Capturing your screen and microphone — everything stays on this Mac."
        case .audioPaused:  return "Still capturing your screen. Microphone capture is paused."
        case .screenPaused: return "Still capturing your microphone. Screen capture is paused."
        case .bothPaused:   return "Screen and microphone capture are both paused."
        case .starting:     return "Starting the on-device recorder…"
        case .idle:         return nil
        case .error(let m): return m
        }
    }

    private var heroDetail: String? {
        guard let since = recorder.recordingSince else { return nil }
        let clock = since.formatted(date: .omitted, time: .shortened)
        let up = recorder.lastHealth?.pipeline?.uptimeSecs ?? 0
        return "Since \(clock) · \(MemoryFormatting.duration(seconds: up))"
    }

    // MARK: - Degraded banner

    /// Non-nil only when recording but `/health` reports a non-"ok" capture status.
    private var degradedMessage: String? {
        guard recorder.status == .recording, let h = recorder.lastHealth else { return nil }
        if h.frameStatus != "ok" { return "Screen capture is degraded — open the log for details." }
        if h.audioStatus != "ok" { return "Microphone capture is degraded — open the log for details." }
        return nil
    }

    private func degradedBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.paused)
            Text(msg).font(Theme.body).foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.paused.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if case .error = recorder.status {
            Button("Restart recorder") { Task { await recorder.restartAfterCrash() } }
                .buttonStyle(.borderedProminent)
        } else {
            HStack(spacing: 10) {
                Button(bothTitle) { Task { await bothAction() } }
                    .buttonStyle(.bordered)
                    .disabled(disableControls)
                Button(audioTitle) { Task { await audioAction() } }
                    .disabled(disableControls)
                Button(screenTitle) { Task { await screenAction() } }
                    .disabled(disableControls)
                Spacer(minLength: 12)
                Button("Reveal recordings") { NSWorkspace.shared.open(recorder.dataFolderURL) }
                    .buttonStyle(.link)
            }
        }
    }

    private var disableControls: Bool {
        switch recorder.status { case .starting, .idle, .error: return true; default: return false }
    }
    private var bothTitle: String   { recorder.status == .bothPaused ? "Resume both" : "Pause both" }
    private var audioTitle: String  {
        switch recorder.status { case .audioPaused, .bothPaused: return "Resume audio"; default: return "Pause audio" }
    }
    private var screenTitle: String {
        switch recorder.status { case .screenPaused, .bothPaused: return "Resume screen"; default: return "Pause screen" }
    }
    private func bothAction() async   { recorder.status == .bothPaused ? await recorder.resumeAll() : await recorder.pauseAll() }
    private func audioAction() async  {
        switch recorder.status { case .audioPaused, .bothPaused: await recorder.resumeAudio(); default: await recorder.pauseAudio() }
    }
    private func screenAction() async {
        switch recorder.status { case .screenPaused, .bothPaused: await recorder.resumeScreen(); default: await recorder.pauseScreen() }
    }

    // MARK: - This session

    @ViewBuilder private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This session").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack(spacing: 12) {
                StatTile(value: intOrDash(recorder.lastHealth?.pipeline?.framesCaptured), label: "screens\ncaptured")
                StatTile(value: intOrDash(recorder.lastHealth?.audioPipeline?.totalWords), label: "words\ntranscribed")
                StatTile(value: intOrDash(recorder.lastHealth?.monitors?.count), label: "displays")
                StatTile(value: intOrDash(recorder.lastHealth?.audioPipeline?.audioDevices?.filter { $0.lowercased().contains("input") }.count), label: "mic\nsources")
            }
            HStack(spacing: 24) {
                if let last = lastCaptureText { metaLine("Last capture", last) }
                if let size = recorder.recordingsSizeBytes { metaLine("Recordings folder", MemoryFormatting.bytes(size)) }
            }
        }
        .opacity(recorder.status == .recording ? 1 : 0.55)
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        (Text(label + " · ").foregroundStyle(Theme.secondaryText) + Text(value).foregroundStyle(Theme.primaryText))
            .font(Theme.caption)
    }

    private var lastCaptureText: String? {
        guard let s = recorder.lastHealth?.lastFrameTimestamp, let d = MemoryFormatting.parseTimestamp(s) else { return nil }
        return MemoryFormatting.relative(from: d)
    }

    private func intOrDash(_ n: Int?) -> String { n.map(String.init) ?? "—" }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mengo Memory keeps a private, on-device record of what you see and hear. Nothing is uploaded.")
                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("View log") { NSWorkspace.shared.open(recorder.recorderLogURL) }
                .buttonStyle(.link).font(Theme.caption)
        }
    }
}

/// A small "big number + small label" tile for the "This session" row.
private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.primaryText)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center).fixedSize()
        }
        .frame(minWidth: 84)
        .padding(.vertical, 12).padding(.horizontal, 10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MemoryPane.swift
git commit -m "MengoDesktop: redesign MemoryPane — status hero, Pause-both control, session stat tiles, privacy line; no screenpipe/paths in the UI"
```

---

## Task 6: Wire "Pause both" into the menu + rename items

**Files:**
- Modify: `Sources/MengoDesktop/MenuBarContent.swift`

- [ ] **Step 1: Update `MenuBarContent.swift`**

In `Sources/MengoDesktop/MenuBarContent.swift`:

(a) In the `// MARK: Memory` section of `body`, add a "Pause both" item *before* `audioItem`, and rename the two "Open …" buttons:

```swift
        // MARK: Memory
        Text("Memory").font(.caption).foregroundStyle(.secondary)
        bothItem
        audioItem
        screenItem
        if case .error = recorder.status {
            Button("Restart recorder") { Task { await recorder.restartAfterCrash() } }
        }
        Button("Reveal recordings") { NSWorkspace.shared.open(recorder.dataFolderURL) }
        Button("View log") { NSWorkspace.shared.open(recorder.recorderLogURL) }
```

(b) Add `bothItem` next to `audioItem`/`screenItem`:

```swift
    @ViewBuilder private var bothItem: some View {
        switch recorder.status {
        case .bothPaused:
            Button("Resume both") { Task { await recorder.resumeAll() } }
        case .recording, .audioPaused, .screenPaused:
            Button("Pause both") { Task { await recorder.pauseAll() } }
        case .starting, .idle, .error:
            Button("Pause both") { }.disabled(true)
        }
    }
```

(c) In `struct MenuBarLabel`, swap the hard-coded colours for the `Theme` tokens:

```swift
    private var color: Color {
        switch status {
        case .recording: return Theme.recording
        case .audioPaused, .screenPaused, .bothPaused: return Theme.paused
        case .error: return Theme.stopped
        case .starting, .idle: return .secondary
        }
    }
```

(Leave `glyph`, the Flow group, the nav buttons, and Quit unchanged.)

- [ ] **Step 2: Build + full test suite**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all tests pass.

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MenuBarContent.swift
git commit -m "MengoDesktop: menu — Pause both / Resume both item; Reveal recordings / View log labels; Theme status colors"
```

---

## Task 7: Update the manual smoke checklist + verify the build

**Files:**
- Modify: `docs/manual-smoke-tests/mengo-phase-2-memory.md`

- [ ] **Step 1: Update the "App behaviour" section**

In `docs/manual-smoke-tests/mengo-phase-2-memory.md`, replace the "App behaviour" bullet list with:

```markdown
## App behaviour (run `open MengoDesktop.app` — needs a human at the machine)

- [ ] Screen Recording + Microphone permission dialogs appear; grant both.
- [ ] Within ~15 s the menu-bar glyph turns **green**. The Memory pane shows **one** status dot (no duplicate `●`), "Recording", the "everything stays on this Mac" subtitle, and a "Since … · …" line.
- [ ] No "Screen capture: ok / Audio capture: ok" rows anywhere — capture-status text appears *only* if `/health` reports a degraded status (amber banner).
- [ ] "This session" shows four stat tiles — screens captured / words transcribed / displays / mic sources — with plausible numbers that climb over time; "Last capture · just now"; "Recordings folder · N GB" once the size is computed.
- [ ] **Pause both** → menu-bar glyph amber, pane shows "Paused", button reads "Resume both"; clicking it → back to green "Recording". (Also: Pause audio / Pause screen individually still work.)
- [ ] **Reveal recordings** opens `~/.screenpipe/` in Finder — and the folder path is *not* shown anywhere in the UI.
- [ ] **View log** opens the recorder log (pane and menu both).
- [ ] Nothing in the Memory pane or the menu says "screenpipe" or shows an engine version.
- [ ] `pkill screenpipe` → within ~30 s the pane shows "⚠ Recorder stopped" + the reason + a prominent **Restart recorder** button; clicking it brings it back to green.
- [ ] Close the main window → app stays in the Dock, glyph still green. **Quit** (⌘Q) → app exits, no orphan `screenpipe`, `~/Library/Logs/MengoDesktop/app.log` has `app terminating`.
```

- [ ] **Step 2: Run the scriptable verification**

```bash
swift build
swift test
plutil -lint Resources/MengoDesktopInfo.plist
```
Expected: build complete; all tests pass; plist OK.

- [ ] **Step 3: Commit**

```bash
git add docs/manual-smoke-tests/mengo-phase-2-memory.md
git commit -m "MengoDesktop: update Phase 2 smoke checklist for the redesigned Memory pane"
```

- [ ] **Step 4: (Optional) build the app and eyeball it**

```bash
./build-mengo.sh
open MengoDesktop.app   # grant TCC, walk the "App behaviour" checklist; quit any leftover screenpipe + the app after
```
(GUI/TCC steps need a human or the computer-use tools — the build/test/plist steps above are the scriptable gate.)

---

## Done criteria

- `swift build` / `swift test` pass.
- The Memory pane: one status dot; capture-status text only when degraded; a status hero with subtitle + "Since …"; a "Pause both" control plus the audio/screen ones; "This session" stat tiles + last-capture + recordings size; a privacy line + "View log"; "Reveal recordings" opens Finder. Nothing says "screenpipe" or shows an engine version, and no raw paths appear in the UI.
- The menu's Memory group has "Pause both" / "Resume both" and "Reveal recordings" / "View log"; the menu-bar glyph uses the `Theme` status colors.
- `Sources/ScreenpipeMenu/` and `Sources/ScreenpipeFlow/` are untouched; only `MengoDesktop` files, tests, and `docs/manual-smoke-tests/mengo-phase-2-memory.md` changed.
- The updated manual smoke checklist passes.
