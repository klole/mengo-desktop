# Mengo Desktop Phase 3b — Mengo Flow, Mode C ("Grab last N minutes") — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Retroactive Flow recording: hit "Grab last N minutes…" (menu or `⌃⌥G`) → a moment-list picker over screenpipe's recent buffer → pick where the task started → "Begin from here" → a `.retroactive` recording session (buffer indicator on the HUD, narrate forward + describe the past) → Stop → synthesize → the pre-narration steps come back flagged `(inferred — verify)`.

**Architecture:** A tiny `ScreenpipeSearchClient` (`GET /search?content_type=ocr`, authed with `RecorderController.screenpipeToken`) feeds a `TimelinePickerView` rendered by `FlowPane` in a new `FlowState.browsingTimeline`; `FlowController.startRetroactive(bufferStart:)` then enters `.recording` with `mode: .retroactive` — and everything downstream (HUD buffer indicator, `ManifestWriter` retroactive serialization, `synthesis-prompt.md`'s pre-narration reconstruction, `SkillFiles` inferred-step rendering) already shipped in 3a. Adds the menu item + the `⌃⌥G` hotkey.

**Tech Stack:** Swift 6, SwiftUI, `@Observable @MainActor`, XCTest, `URLSession`, Carbon `RegisterEventHotKey`.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-phase-3b-flow-modec-design.md`](../specs/2026-05-12-mengo-phase-3b-flow-modec-design.md)

**Branch:** `claude/kind-volhard-f7e189` (already off `main` at `609799f` — the 3b spec commit).

**V1 reference (same repo):** `Sources/ScreenpipeFlow/ScreenpipeClient.swift` (the `thumbnailIndex` / `parseThumbnailIndex` / `parseISO8601` logic to port) and `Sources/ScreenpipeFlow/TimelineWindow.swift` (the picker layout).

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/ScreenpipeSearchClient.swift` | new | `Moment` value type; `MomentIndexing` protocol; `ScreenpipeSearchClient` impl over `/search?content_type=ocr`; pure `parseMomentIndex(_:)` + `decimate(_:minIntervalSec:)`; lenient ISO8601 parse. |
| `Sources/MengoDesktop/FlowState.swift` | modify | Add `case browsingTimeline`. |
| `Sources/MengoDesktop/FlowController.swift` | modify | Inject `MomentIndexing`; `beginBrowsingTimeline()`, `cancelBrowsingTimeline()`, `startRetroactive(bufferStart:)`, `loadMoments(lookbackMinutes:)`; `toggleRecording` cancels from `.browsingTimeline`; `live(…)` wires a real `ScreenpipeSearchClient(token:)`. |
| `Sources/MengoDesktop/TimelinePickerView.swift` | new | The `.browsingTimeline` UI — look-back picker + moment list + Cancel / Begin-from-here. |
| `Sources/MengoDesktop/FlowPane.swift` | modify | Render `.browsingTimeline` → `TimelinePickerView`; idle "Grab last N minutes" button; retroactive recording-state text (buffer + alt hint). |
| `Sources/MengoDesktop/MenuBarContent.swift` | modify | "Grab last 5 minutes… ⌃⌥G" enabled (→ `beginBrowsingTimeline` + raise window) / "Cancel timeline picker" when browsing. |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | modify | Register `⌃⌥G`; notification-observer to raise the main window + select Flow + `beginBrowsingTimeline`. |
| `Tests/MengoDesktopTests/ScreenpipeSearchClientTests.swift` | new | parse + decimate. |
| `Tests/MengoDesktopTests/FlowControllerTests.swift` | modify | browsingTimeline transitions; `startRetroactive`; `loadMoments`. |
| `docs/manual-smoke-tests/mengo-phase-3b-flow-modec.md` | new | Mode-C walk-through. |

---

## Task 1: `ScreenpipeSearchClient` — moment index over `/search` (TDD)

**Files:** Create `Sources/MengoDesktop/ScreenpipeSearchClient.swift`, `Tests/MengoDesktopTests/ScreenpipeSearchClientTests.swift`.

- [ ] **Step 1: Write the failing tests** (`Tests/MengoDesktopTests/ScreenpipeSearchClientTests.swift`):

```swift
import XCTest
@testable import MengoDesktop

final class ScreenpipeSearchClientTests: XCTestCase {

    func test_parseMomentIndex_decodesOCRRows_skipsOthers_tolerantTimestamps() {
        let json = Data("""
        { "data": [
          { "type": "OCR", "content": { "timestamp": "2026-05-12T14:25:00.123Z", "app_name": "Google Chrome", "window_name": "Staging Admin" } },
          { "type": "OCR", "content": { "timestamp": "2026-05-12T14:27:00Z", "app_name": "Slack", "window_name": "#growth" } },
          { "type": "Audio", "content": { "timestamp": "2026-05-12T14:26:00Z", "transcription": "blah" } },
          { "type": "OCR", "content": { "timestamp": "2026-05-12T14:30:00Z" } }
        ] }
        """.utf8)
        let moments = ScreenpipeSearchClient.parseMomentIndex(json)
        XCTAssertEqual(moments.count, 3)                       // the Audio row is skipped
        XCTAssertEqual(moments.first?.appName, "Google Chrome")  // sorted oldest-first
        XCTAssertEqual(moments.first?.windowName, "Staging Admin")
        XCTAssertEqual(moments[1].appName, "Slack")
        XCTAssertEqual(moments[2].appName, "")                 // missing app_name → ""
        XCTAssertEqual(moments[2].windowName, "")
        // 14:25:00.123 < 14:27:00 < 14:30:00
        XCTAssertTrue(moments[0].timestamp < moments[1].timestamp)
        XCTAssertTrue(moments[1].timestamp < moments[2].timestamp)
    }

    func test_parseMomentIndex_malformed_returnsEmpty() {
        XCTAssertTrue(ScreenpipeSearchClient.parseMomentIndex(Data("nope".utf8)).isEmpty)
        XCTAssertTrue(ScreenpipeSearchClient.parseMomentIndex(Data(#"{"ok":true}"#.utf8)).isEmpty)
    }

    func test_decimate_keepsRoughlyOnePerInterval() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let moments = (0..<10).map { i in
            Moment(timestamp: base.addingTimeInterval(Double(i) * 5), appName: "App", windowName: "w\(i)")  // every 5 s
        }
        let kept = ScreenpipeSearchClient.decimate(moments, minIntervalSec: 15)
        // 0s, 15s, 30s, 45s → at most every 15 s
        XCTAssertEqual(kept.map(\.windowName), ["w0", "w3", "w6", "w9"])
    }
}
```

- [ ] **Step 2: Run, verify it fails.** `swift test --filter ScreenpipeSearchClientTests` — FAIL (`ScreenpipeSearchClient` / `Moment` not found).

- [ ] **Step 3: Implement `Sources/MengoDesktop/ScreenpipeSearchClient.swift`:**

```swift
import Foundation

/// One moment from screenpipe's recent capture — used by the "grab last N minutes"
/// picker. Carries enough to recognise *when* a task started without fetching an image.
struct Moment: Equatable, Hashable, Identifiable {
    let timestamp: Date
    let appName: String
    let windowName: String
    var id: Date { timestamp }
}

/// Abstracts the screenpipe `/search` query so `FlowController` tests can stub it.
protocol MomentIndexing: Sendable {
    func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment]
}

/// Queries screenpipe's local HTTP API (`GET /search?content_type=ocr`) for a
/// decimated list of recent moments, authed with the recorder's per-launch token.
/// (Mirrors V1's `ScreenpipeClient.thumbnailIndex`, minus the `auth token` discovery
/// — V2's token comes from `RecorderController.screenpipeToken`.)
struct ScreenpipeSearchClient: MomentIndexing {
    let token: String
    var baseURL = URL(string: "http://127.0.0.1:3030")!
    var session: URLSession = .shared
    var decimateIntervalSec: TimeInterval = 15

    enum SearchError: Error, LocalizedError {
        case notResponding, http(Int)
        var errorDescription: String? {
            switch self {
            case .notResponding: return "the recorder isn't responding"
            case .http(let c):   return "the recorder returned HTTP \(c)"
            }
        }
    }

    func momentIndex(from start: Date, to end: Date, limit: Int) async throws -> [Moment] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "content_type", value: "ocr"),
            .init(name: "start_time", value: Self.iso.string(from: start)),
            .init(name: "end_time", value: Self.iso.string(from: end)),
            .init(name: "limit", value: String(limit)),
        ]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response): (Data, URLResponse)
        do { (data, response) = try await session.data(for: req) }
        catch let e as URLError where e.code == .cannotConnectToHost || e.code == .timedOut { throw SearchError.notResponding }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw SearchError.http(http.statusCode) }
        return Self.decimate(Self.parseMomentIndex(data), minIntervalSec: decimateIntervalSec)
    }

    // MARK: pure helpers (tested directly)

    static func parseMomentIndex(_ data: Data) -> [Moment] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["data"] as? [[String: Any]] else { return [] }
        var out: [Moment] = []
        for row in rows {
            guard ((row["type"] as? String)?.lowercased() == "ocr"),
                  let content = row["content"] as? [String: Any],
                  let ts = content["timestamp"] as? String,
                  let date = parseISO8601(ts) else { continue }
            out.append(Moment(timestamp: date,
                              appName: (content["app_name"] as? String) ?? "",
                              windowName: (content["window_name"] as? String) ?? ""))
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    /// Keeps at most one moment per `minIntervalSec` (walking oldest→newest).
    static func decimate(_ moments: [Moment], minIntervalSec: TimeInterval) -> [Moment] {
        var last: Date?
        var out: [Moment] = []
        for m in moments.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let l = last, m.timestamp.timeIntervalSince(l) < minIntervalSec { continue }
            out.append(m); last = m.timestamp
        }
        return out
    }

    /// screenpipe emits ISO8601 with-or-without fractional seconds. Try fractional, fall back.
    static func parseISO8601(_ s: String) -> Date? {
        let frac = ISO8601DateFormatter(); frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = frac.date(from: s) { return d }
        let plain = ISO8601DateFormatter(); plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    private static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()
}
```

- [ ] **Step 4: Run, verify pass.** `swift test --filter ScreenpipeSearchClientTests` — PASS (3 tests).

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/ScreenpipeSearchClient.swift Tests/MengoDesktopTests/ScreenpipeSearchClientTests.swift && git commit -m "MengoDesktop: ScreenpipeSearchClient — moment index over /search?content_type=ocr (TDD)"`

---

## Task 2: `FlowState.browsingTimeline` + `FlowController` Mode-C methods (TDD)

**Files:** Modify `Sources/MengoDesktop/FlowState.swift`, `Sources/MengoDesktop/FlowController.swift`, `Tests/MengoDesktopTests/FlowControllerTests.swift`.

- [ ] **Step 1: Add `.browsingTimeline` to `FlowState`** (`FlowState.swift`):

```swift
enum FlowState: Equatable {
    case idle
    case browsingTimeline
    case recording(FlowSession)
    case synthesizing(URL)
    case reviewing(URL)
    case error(String)
}
```

(This forces exhaustive-switch updates in `FlowPane` / `MenuBarContent` — handled in Tasks 4–5; for now `swift build` will flag them. Add a temporary `case .browsingTimeline: EmptyView()` in `FlowPane` and `default`/`case .browsingTimeline:` no-op in `MenuBarContent` just to keep the build green between tasks, or do Tasks 4–5 in the same sitting. The plan assumes you fill them properly in 4–5.)

- [ ] **Step 2: Add the failing tests** to `FlowControllerTests.swift`:

```swift
struct StubMoments: MomentIndexing {
    var moments: [Moment] = []
    func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment] { moments }
}
// extend makeController with `moments: MomentIndexing = StubMoments()` and pass it through to FlowController.init.

func test_beginBrowsingTimeline_fromIdle() async {
    let c = makeController()
    c.beginBrowsingTimeline()
    XCTAssertEqual(c.flowState, .browsingTimeline)
}
func test_beginBrowsingTimeline_noopWhenNotIdle() async {
    let c = makeController()
    await c.start()                       // → .recording
    c.beginBrowsingTimeline()
    guard case .recording = c.flowState else { return XCTFail("should still be .recording") }
}
func test_cancelBrowsingTimeline_returnsToIdle() {
    let c = makeController()
    c.beginBrowsingTimeline()
    c.cancelBrowsingTimeline()
    XCTAssertEqual(c.flowState, .idle)
}
func test_startRetroactive_entersRecording_withRetroactiveSession() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let c = makeController(now: { t })
    c.beginBrowsingTimeline()
    let bufferStart = Date(timeIntervalSince1970: 999_400)   // 10 min earlier
    t = Date(timeIntervalSince1970: 1_000_000)
    await c.startRetroactive(bufferStart: bufferStart)
    guard case .recording(let s) = c.flowState else { return XCTFail("expected .recording, got \(c.flowState)") }
    XCTAssertEqual(s.mode, .retroactive)
    XCTAssertEqual(s.bufferRangeStart, bufferStart)
    XCTAssertEqual(s.activeRecordingStart, t)
}
func test_startRetroactive_blockedByPreflight_staysBrowsing() async {
    let c = makeController(claudeExecutable: nil)            // → .claudeNotFound; onPreflightFailure is a no-op in tests
    c.beginBrowsingTimeline()
    await c.startRetroactive(bufferStart: Date())
    XCTAssertEqual(c.flowState, .browsingTimeline)
}
func test_loadMoments_returnsStubList() async throws {
    let m = [Moment(timestamp: Date(timeIntervalSince1970: 1), appName: "A", windowName: "w")]
    let c = makeController(moments: StubMoments(moments: m))
    let got = try await c.loadMoments(lookbackMinutes: 30)
    XCTAssertEqual(got, m)
}
```

- [ ] **Step 3: Run, verify fails.** `swift test --filter FlowControllerTests` — the new ones FAIL.

- [ ] **Step 4: Implement in `FlowController.swift`.**

(a) Add the dep:

```swift
@ObservationIgnored private let moments: MomentIndexing
```

(b) In `init`, add a parameter `moments: MomentIndexing = ScreenpipeSearchClient.placeholder` — wait, the real one needs a token. Make it injectable with no default and supply it from `live(…)`; in `init`, accept `moments: MomentIndexing` (no default) — but that breaks call sites that don't pass it. Instead: keep a sensible default that's harmless when there's no token. Cleanest: `moments: MomentIndexing = NullMomentIndexing()` where `struct NullMomentIndexing: MomentIndexing { func momentIndex(...) async throws -> [Moment] { [] } }` (lives in `ScreenpipeSearchClient.swift`), and `live(…)` overrides it with `ScreenpipeSearchClient(token: recorder.screenpipeToken)`. So:

```swift
// in ScreenpipeSearchClient.swift, add:
struct NullMomentIndexing: MomentIndexing { func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment] { [] } }
```

```swift
// FlowController.init params: ... , moments: MomentIndexing = NullMomentIndexing(), ...
self.moments = moments
```

```swift
// FlowController.live(...):  add `moments: ScreenpipeSearchClient(token: recorder.screenpipeToken),`
```

(c) The methods:

```swift
func beginBrowsingTimeline() { if case .idle = flowState { flowState = .browsingTimeline } }
func cancelBrowsingTimeline() { if case .browsingTimeline = flowState { flowState = .idle } }

func loadMoments(lookbackMinutes: Int) async throws -> [Moment] {
    let now = self.now()
    return try await moments.momentIndex(from: now.addingTimeInterval(-Double(lookbackMinutes) * 60), to: now, limit: 400)
}

func startRetroactive(bufferStart: Date) async {
    // Reached from .browsingTimeline (the picker). Preflight; on pass enter .recording.
    guard case .browsingTimeline = flowState else { return }
    if let failure = await preflight() { onPreflightFailure(failure); return }   // stays .browsingTimeline
    let session = FlowSession(mode: .retroactive, bufferRangeStart: bufferStart, activeRecordingStart: now(), endTime: nil)
    lastSession = session
    flowState = .recording(session)
    hudShow(session) { [weak self] in Task { @MainActor in await self?.stop() } }
}
```

(d) `toggleRecording` — add the browsing case:

```swift
func toggleRecording() async {
    switch flowState {
    case .recording: await stop()
    case .browsingTimeline: cancelBrowsingTimeline()
    case .idle, .error: await start()
    default: break
    }
}
```

- [ ] **Step 5: Run, verify pass.** `swift build && swift test --filter FlowControllerTests` — PASS. (FlowPane/MenuBarContent may not compile yet — if so, add the temporary stubs from Step 1's note and rebuild; Tasks 4–5 replace them.)

- [ ] **Step 6: Commit.** `git add Sources/MengoDesktop/FlowState.swift Sources/MengoDesktop/FlowController.swift Sources/MengoDesktop/ScreenpipeSearchClient.swift Tests/MengoDesktopTests/FlowControllerTests.swift && git commit -m "MengoDesktop: FlowController Mode-C — browsingTimeline / startRetroactive / loadMoments (TDD)"`

---

## Task 3: `TimelinePickerView`

**Files:** Create `Sources/MengoDesktop/TimelinePickerView.swift`. No tests (UI) — `swift build`.

- [ ] **Step 1: Implement `Sources/MengoDesktop/TimelinePickerView.swift`:**

```swift
import SwiftUI

/// The `.browsingTimeline` UI — "pick where the task started" over screenpipe's
/// recent buffer (a moment list, not thumbnails). Adapted from V1's `TimelineWindow`.
struct TimelinePickerView: View {
    let flow: FlowController

    @State private var lookbackMinutes = 30
    @State private var moments: [Moment] = []
    @State private var selected: Moment?
    @State private var loading = false
    @State private var loadError: String?

    private static let timeFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm:ss a"; return f }()

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Grab last N minutes").font(Theme.title).foregroundStyle(Theme.primaryText)
                Text("Pick the moment your task started. Mengo will record forward from now — and the synthesizer reconstructs the part before this point from screen + accessibility (those steps come back flagged for you to verify).")
                    .font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Text("Look back:").font(Theme.body).foregroundStyle(Theme.secondaryText)
                Picker("", selection: $lookbackMinutes) {
                    Text("15 min").tag(15); Text("30 min").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120)
                }.labelsHidden().frame(width: 110).onChange(of: lookbackMinutes) { _, _ in Task { await reload() } }
                Button("Reload") { Task { await reload() } }.buttonStyle(.bordered)
                Spacer(minLength: 0)
            }
            Group {
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else if let e = loadError {
                    VStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.paused)
                        Text(e).font(Theme.body).foregroundStyle(Theme.secondaryText)
                    }.frame(maxWidth: .infinity, minHeight: 200)
                } else if moments.isEmpty {
                    Text("No screenpipe data in that range. Try a longer look-back.")
                        .font(Theme.body).foregroundStyle(Theme.mutedText).frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(moments.reversed().enumerated()), id: \.element.id) { idx, m in
                                row(m)
                                if idx < moments.count - 1 { Divider().overlay(Theme.separator) }
                            }
                        }
                    }
                    .frame(minHeight: 240, maxHeight: 360)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
                }
            }
            if let sel = selected {
                let secs = max(0, Int(Date().timeIntervalSince(sel.timestamp)))
                Text("Selected: \(Self.timeFmt.string(from: sel.timestamp)) → now  (\(secs / 60)m \(secs % 60)s)")
                    .font(Theme.caption).foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Spacer(minLength: 0)
                Button("Cancel") { flow.cancelBrowsingTimeline() }.buttonStyle(.bordered)
                Button("Begin from here") { if let m = selected { Task { await flow.startRetroactive(bufferStart: m.timestamp) } } }
                    .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(selected == nil).keyboardShortcut(.return)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
        .task { await reload() }
    }

    private func row(_ m: Moment) -> some View {
        let isSel = selected == m
        return HStack(spacing: 12) {
            Text(Self.timeFmt.string(from: m.timestamp)).font(.system(.body, design: .monospaced)).foregroundStyle(isSel ? .white : Theme.secondaryText).frame(width: 110, alignment: .leading)
            Text(m.appName.isEmpty ? "—" : m.appName).font(Theme.body.weight(.medium)).foregroundStyle(isSel ? .white : Theme.primaryText)
            Text(m.windowName).font(Theme.body).foregroundStyle(isSel ? .white.opacity(0.85) : Theme.mutedText).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 7).padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(isSel ? Theme.accent : Color.clear)
        .onTapGesture { selected = m }
    }

    private func reload() async {
        loading = true; loadError = nil; selected = nil
        do { moments = try await flow.loadMoments(lookbackMinutes: lookbackMinutes) }
        catch { loadError = error.localizedDescription }
        loading = false
    }
}
```

- [ ] **Step 2: Build.** `swift build` — `Build complete!` (with Task 4 done, or with the temporary `FlowPane` stub from Task 2's note).

- [ ] **Step 3: Commit.** `git add Sources/MengoDesktop/TimelinePickerView.swift && git commit -m "MengoDesktop: TimelinePickerView — 'grab last N minutes' moment-list picker"`

---

## Task 4: `FlowPane` — render `.browsingTimeline`, idle "Grab last N minutes" button, retroactive recording text

**Files:** Modify `Sources/MengoDesktop/FlowPane.swift`. No tests — `swift build`.

- [ ] **Step 1.** In `FlowPane.body`'s switch, replace any temporary `.browsingTimeline` stub with:

```swift
case .browsingTimeline: TimelinePickerView(flow: flow)
```

- [ ] **Step 2.** In the `idle` view, replace the greyed "Grab last N minutes… — coming soon" `Label` with an active button next to "Start recording":

```swift
Button { flow.beginBrowsingTimeline() } label: { Label("Grab last N minutes…", systemImage: "clock.arrow.circlepath") }
    .buttonStyle(.bordered)
Text("⌃⌥G").font(Theme.caption).foregroundStyle(Theme.mutedText)
```

- [ ] **Step 3.** In the `recording(_ session:)` view, after the elapsed-time line, add (when the session is retroactive):

```swift
if let bs = session.bufferRangeStart {
    let buf = max(0, Int(session.activeRecordingStart.timeIntervalSince(bs)))
    Text("Buffer: \(buf / 60)m \(buf % 60)s — the synthesizer will reconstruct that earlier window from screen + accessibility.")
        .font(Theme.caption).foregroundStyle(Theme.mutedText)
}
Text(session.bufferRangeStart == nil
     ? "Narrate your task as you go. Use the floating panel's Stop button (or ⌃⌥R) when you're done."
     : "Narrate forward — and you can also describe what happened earlier. Stop with the floating panel or ⌃⌥R when you're done.")
    .font(Theme.body).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
```

(replacing the existing single "Narrate your task…" line).

- [ ] **Step 4: Build.** `swift build` — `Build complete!`

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/FlowPane.swift && git commit -m "MengoDesktop: FlowPane — render the timeline picker; idle 'Grab last N minutes' button; retroactive recording text"`

---

## Task 5: `MenuBarContent` — un-disable "Grab last 5 minutes…" / "Cancel timeline picker"

**Files:** Modify `Sources/MengoDesktop/MenuBarContent.swift`. No tests — `swift build`.

- [ ] **Step 1.** In the Flow group, after the Start/Stop switch, replace `Button("Grab last 5 minutes…") { }.disabled(true)` with:

```swift
switch flow.flowState {
case .idle, .error:
    Button("Grab last 5 minutes…") { flow.beginBrowsingTimeline(); reveal(.flow) }
        .keyboardShortcut("g", modifiers: [.control, .option])
case .browsingTimeline:
    Button("Cancel timeline picker") { flow.cancelBrowsingTimeline() }
default:
    Button("Grab last 5 minutes…") { }.disabled(true)
}
```

(If the Start/Stop `switch flow.flowState` directly above already has a `case .browsingTimeline:`, leave that one as the existing "Reviewing"/etc. handling — actually it currently has `.idle/.error`, `.recording`, `.synthesizing`, `.reviewing`; with `.browsingTimeline` added to the enum that switch needs a `case .browsingTimeline:` — handle it as "Start recording…" disabled, or just route it the same as `.idle` (but the user is in the picker, so "Start recording…" doesn't make sense — make the Start/Stop item read "Choosing a start point…" disabled while `.browsingTimeline`). Concretely, the Start/Stop block becomes:)

```swift
switch flow.flowState {
case .idle, .error:
    Button("Start recording…") { Task { await flow.start() } }.keyboardShortcut("r", modifiers: [.control, .option])
case .recording:
    Button("Stop recording") { Task { await flow.stop() } }.keyboardShortcut("r", modifiers: [.control, .option])
case .browsingTimeline:
    Button("Choosing a start point…") { reveal(.flow) }
case .synthesizing:
    Button("Synthesizing skill…") { }.disabled(true)
case .reviewing:
    Button("Reviewing skill…") { reveal(.flow) }
}
```

- [ ] **Step 2: Build.** `swift build` — `Build complete!`

- [ ] **Step 3: Commit.** `git add Sources/MengoDesktop/MenuBarContent.swift && git commit -m "MengoDesktop: menu — enable 'Grab last 5 minutes… ⌃⌥G' / 'Cancel timeline picker'"`

---

## Task 6: `⌃⌥G` global hotkey + window-raise

**Files:** Modify `Sources/MengoDesktop/MengoDesktopApp.swift`. No tests — `swift build` + relaunch.

- [ ] **Step 1.** Add the notification name (top of the file, near `import`s):

```swift
extension Notification.Name { static let openFlowTimeline = Notification.Name("MengoDesktop.openFlowTimeline") }
```

- [ ] **Step 2.** In `AppDelegate.applicationDidFinishLaunching`, after the `recordToggle` registration, add:

```swift
AppDelegate.sharedHotkeys?.register(HotkeyManager.grabLast) {
    NotificationCenter.default.post(name: .openFlowTimeline, object: nil)
}
```

- [ ] **Step 3.** Wire an observer. The `MengoDesktopApp.body`'s `MenuBarExtra` label currently is just `MenuBarLabel(status: recorder.status)`. Wrap it so a `.task` modifier can install the observer (mirroring V1's "open library" pattern):

```swift
MenuBarExtra {
    MenuBarContent(appState: appState, recorder: recorder, flow: flow)
} label: {
    MenuBarLabel(status: recorder.status)
        .task {
            for await _ in NotificationCenter.default.notifications(named: .openFlowTimeline).map({ _ in () }) {
                openWindow(id: "main")
                appState.selectedSection = .flow
                flow.beginBrowsingTimeline()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
}
```

(Add `@Environment(\.openWindow) private var openWindow` to `MengoDesktopApp` if not already there. The `for await` loop runs for the lifetime of the menu-bar label, which is the lifetime of the app.)

- [ ] **Step 4: Build + full tests.** `swift build` then `swift test` — `Build complete!` and all suites pass.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/MengoDesktopApp.swift && git commit -m "MengoDesktop: ⌃⌥G global hotkey → opens the Flow timeline picker"`

---

## Task 7: Smoke checklist; full test run; rebuild + relaunch; merge to main

**Files:** Create `docs/manual-smoke-tests/mengo-phase-3b-flow-modec.md`.

- [ ] **Step 1.** Write `docs/manual-smoke-tests/mengo-phase-3b-flow-modec.md` — sections: *Build & tests* (`swift build`; `swift test`; `./build-mengo.sh` produces `MengoDesktop.app`, codesign verifies). *App behaviour*:
  - Do something for a couple of minutes, then **menu → "Grab last 5 minutes…"** (or `⌃⌥G` — even with the main window closed, it raises the window onto the Flow tab): the Flow pane shows the picker; within a moment it lists recent moments (`h:mm:ss · app · window title`, newest first); changing the look-back re-queries; `[Reload]` re-queries.
  - Pick a moment → the "Selected: … → now (Nm Ns)" caption appears → **Begin from here** → the picker closes; a floating HUD appears showing `● Recording 0:NN  Buffer: Nm Ns` and the "Narrate forward; you can also describe what happened earlier." hint; the Flow pane's recording text also shows the buffer line.
  - Continue the task while narrating, and also narrate something about the *earlier* (pre-pick) part. Stop → synthesis → in the **Review**, the SKILL.md preview has a top note flagging some steps for verification, and the step list shows the early ones as "(inferred — verify)".
  - Save → in the Library; invoke via `claude` — confirm the intent works.
  - From the picker, **Cancel** (button or `⌃⌥G` again or the menu's "Cancel timeline picker") → back to the Flow idle pane.
  - A look-back range with no screenpipe data → "No screenpipe data in that range. Try a longer look-back." `[Begin from here]` stays disabled.
  - With the recorder paused / `claude` not on PATH → "Begin from here" shows the standard preflight alert and the picker stays open.
  - Start a Mode-C recording, then **quit the app** mid-recording → relaunch → "An earlier recording was interrupted — synthesize it?" → yes → it synthesizes the whole grabbed window (a `mode: retroactive` recovery manifest).
  - **Regression:** Mode A (`⌃⌥R` proactive) still works; the Memory pane still works.

- [ ] **Step 2: Full test run.** `swift test` — all suites PASS.

- [ ] **Step 3: Rebuild + re-sign.** `./build-mengo.sh` — completes; `codesign --verify --deep --strict MengoDesktop.app` passes.

- [ ] **Step 4: Relaunch + eyeball.** Quit any running MengoDesktop, `open ./MengoDesktop.app`. Verify the Flow pane's idle "Grab last N minutes…" button opens the picker (and the picker lists moments, since the recorder's been running); Cancel returns to idle. (A real Mode-C record→synthesize needs a human + narration — that's the checklist.)

- [ ] **Step 5: Commit + merge.** `git add docs/manual-smoke-tests/mengo-phase-3b-flow-modec.md && git commit -m "MengoDesktop: Phase 3b smoke checklist"`. Then fast-forward `main`: `git -C /Users/kylebell/screenpipe merge --ff-only claude/kind-volhard-f7e189`. (Tag `mengo-v2-phase-3b-flow-modec` once the human-run checklist passes — not yet.)

---

## Self-review notes

- **Spec coverage:** `ScreenpipeSearchClient` / `Moment` / `MomentIndexing` / parse / decimate → T1; `FlowState.browsingTimeline` + `FlowController` (`beginBrowsingTimeline` / `cancelBrowsingTimeline` / `startRetroactive` / `loadMoments` / `toggleRecording` browsing case / `live` wiring) → T2; `TimelinePickerView` → T3; `FlowPane` (render `.browsingTimeline`, idle "Grab" button, retroactive recording text) → T4; `MenuBarContent` ("Grab last 5 minutes… ⌃⌥G" / "Cancel timeline picker") → T5; `⌃⌥G` hotkey + window-raise → T6; tests → T1–2; smoke checklist + merge → T7. The "already shipped in 3a" items (HUD buffer indicator, `ManifestWriter` retroactive, `synthesis-prompt.md`, `SkillFiles` inferred rendering, `screenpipeToken`) need no work — confirmed in the spec. ✅
- **Placeholder scan:** the only deferred bits are the spec's "open questions" (the `/search` response shape — handled by the *tolerant* parser that skips non-matching rows; the ISO8601 leniency — a concrete `parseISO8601` is in T1; the `⌃⌥G` window-raise — a concrete `NotificationCenter` + `.task` observer is in T6). No "TODO/handle errors" left; every code step has the code. The "temporary stub between Task 2 and Tasks 4–5" is called out explicitly. ✅
- **Type consistency:** `Moment`, `MomentIndexing`, `ScreenpipeSearchClient`, `NullMomentIndexing`, `StubMoments`; `ScreenpipeSearchClient.parseMomentIndex` / `.decimate` / `.parseISO8601`; `FlowState.browsingTimeline`; `FlowController.beginBrowsingTimeline` / `cancelBrowsingTimeline` / `startRetroactive(bufferStart:)` / `loadMoments(lookbackMinutes:)` referenced identically across T1–T7 and the views. `FlowSession(mode:bufferRangeStart:activeRecordingStart:endTime:)` matches the 3a definition. ✅
