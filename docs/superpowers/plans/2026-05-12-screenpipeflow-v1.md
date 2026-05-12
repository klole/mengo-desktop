# ScreenpipeFlow V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build V1 of ScreenpipeFlow — a separate macOS Swift app that lets the user demonstrate a task (proactively or by reaching into screenpipe's buffer retroactively), then synthesizes a reusable Claude Code skill via `claude -p`. No Anthropic API tokens spent.

**Architecture:** A new `ScreenpipeFlow` executable target in the existing `Package.swift`, sharing the repo with ScreenpipeMenu (Tool 1). Tool 2 reads from screenpipe's HTTP API for previews and shells out to `claude -p` for synthesis. Tool 1 and Tool 2 don't call each other at runtime. See spec at [`docs/superpowers/specs/2026-05-12-screenpipeflow-design.md`](../specs/2026-05-12-screenpipeflow-design.md).

**Tech Stack:** Swift 6, SwiftUI (`MenuBarExtra`, `Window` scenes), `@Observable` `@MainActor` state, `URLSession` for screenpipe HTTP, `Process` for `claude` subprocess, `Carbon.HIToolbox` for global hotkeys, XCTest for unit/integration tests, ad-hoc codesign matching Tool 1's distribution pattern.

---

## File structure (new files relative to repo root)

```
Package.swift                                  modified — add ScreenpipeFlow target + test target
Resources/ScreenpipeFlowInfo.plist             new — separate plist (different bundle id from Tool 1)
Resources/synthesis-prompt.md                  new — bootstrap prompt for `claude -p`
Sources/ScreenpipeFlow/
├── ScreenpipeFlowApp.swift                    @main, AppDelegate, MenuBarExtra scene, StatusBarLabel, MenuView
├── AppState.swift                             @Observable orchestrator (session state, library, screenpipe status)
├── RecordingSession.swift                     value type + SessionState enum + FlowEntry
├── RecordingController.swift                  preflight + start/stop + triggers synthesis
├── ScreenpipeClient.swift                     HTTP wrapper over 127.0.0.1:3030
├── ManifestWriter.swift                       JSON manifest serialization
├── Slug.swift                                 name → kebab-case slug + collision suffixing
├── SynthesisRunner.swift                      spawn `claude -p`, capture stdout/stderr, parse status
├── HotkeyManager.swift                        Carbon global hotkey registration
├── Logger.swift                               file-based logging
├── RecordingHUD.swift                         floating non-activating panel during recording
├── TimelineWindow.swift                       mode C thumbnail strip + start-point selection
├── ReviewWindow.swift                         post-synthesis review (markdown preview, params, save)
└── LibraryWindow.swift                        list of created flows

Tests/ScreenpipeFlowTests/
├── SlugTests.swift
├── RecordingSessionTests.swift
├── ManifestWriterTests.swift
├── ScreenpipeClientTests.swift                fixture-driven HTTP parsing
├── SynthesisRunnerTests.swift                 fake subprocess via custom Process URL
└── AppStateTests.swift                        state transition matrix

build-flow.sh                                  new — .app bundle assembly for ScreenpipeFlow
install.sh                                     modified — also install ScreenpipeFlow.app
docs/manual-smoke-tests/screenpipeflow-v1.md   new — pre-release checklist

evals/screenpipeflow/                          new — synthesis regression eval harness
├── fixtures/                                  saved recordings (manifest + screenpipe data tarball)
├── run-evals.sh                               drives the eval loop
└── README.md                                  how to add a fixture, how to run
```

---

## Task 1: Bootstrap ScreenpipeFlow target

**Files:**
- Modify: `Package.swift`
- Create: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`
- Create: `Sources/ScreenpipeFlow/AppState.swift`
- Create: `Resources/ScreenpipeFlowInfo.plist`
- Create: `Tests/ScreenpipeFlowTests/AppStateTests.swift`

Goal of this task: a new executable target that builds, launches, shows a menu bar item with just "Quit", and has a placeholder `AppState` with one test passing. Sets up the scaffolding everything else hangs off.

- [ ] **Step 1: Update `Package.swift` with the new target.**

Replace the entire file with:

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ScreenpipeMenu",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "ScreenpipeMenu",
            path: "Sources/ScreenpipeMenu"
        ),
        .testTarget(
            name: "ScreenpipeMenuTests",
            dependencies: ["ScreenpipeMenu"],
            path: "Tests/ScreenpipeMenuTests"
        ),
        .executableTarget(
            name: "ScreenpipeFlow",
            path: "Sources/ScreenpipeFlow"
        ),
        .testTarget(
            name: "ScreenpipeFlowTests",
            dependencies: ["ScreenpipeFlow"],
            path: "Tests/ScreenpipeFlowTests"
        )
    ]
)
```

- [ ] **Step 2: Create the Info.plist for the new app.**

Create `Resources/ScreenpipeFlowInfo.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>ScreenpipeFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.mengo.screenpipeflow</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>ScreenpipeFlow</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>ScreenpipeFlow may invoke the Claude Code CLI to synthesize skills from your recordings.</string>
</dict>
</plist>
```

- [ ] **Step 3: Write the failing test for AppState placeholder.**

Create `Tests/ScreenpipeFlowTests/AppStateTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

@MainActor
final class AppStateTests: XCTestCase {

    func testInitialStateIsIdle() {
        let state = AppState()
        if case .idle = state.sessionState { return }
        XCTFail("expected .idle, got \(state.sessionState)")
    }
}
```

- [ ] **Step 4: Run the test — verify it fails (AppState doesn't exist).**

Run: `swift test --filter ScreenpipeFlowTests`
Expected: compile error — `cannot find 'AppState' in scope`.

- [ ] **Step 5: Create `Sources/ScreenpipeFlow/AppState.swift` with a minimal placeholder.**

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case error(String)
    }

    private(set) var sessionState: SessionState = .idle
}
```

- [ ] **Step 6: Create `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` — minimal @main.**

```swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedState: AppState?
}

@main
struct ScreenpipeFlowApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("ScreenpipeFlow", systemImage: "waveform.circle") {
            Text("ScreenpipeFlow").font(.headline)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 7: Run the test — verify it passes.**

Run: `swift test --filter ScreenpipeFlowTests`
Expected: 1 test passes.

- [ ] **Step 8: Smoke-test the app launches and shows a menu bar item.**

Run: `swift run ScreenpipeFlow`
Expected: a `waveform.circle` icon appears in the menu bar. Clicking it shows "ScreenpipeFlow" header and a "Quit" item. Quit terminates the process.

Kill it with `pkill -f ScreenpipeFlow` if Quit doesn't work (should work, but if hung, force-kill).

- [ ] **Step 9: Commit.**

```bash
git add Package.swift Resources/ScreenpipeFlowInfo.plist Sources/ScreenpipeFlow Tests/ScreenpipeFlowTests
git commit -m "ScreenpipeFlow: bootstrap executable target with menu bar stub"
```

---

## Task 2: Logger

**Files:**
- Create: `Sources/ScreenpipeFlow/Logger.swift`
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`

Pattern matches Tool 1's `freopen`-based redirect of stdout/stderr to a log file, plus a convenience `log()` function.

- [ ] **Step 1: Create `Sources/ScreenpipeFlow/Logger.swift`.**

```swift
import Foundation

enum Logger {
    static let logsDir: URL = {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/ScreenpipeFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let appLogURL: URL = logsDir.appendingPathComponent("app.log")

    /// Redirect stdout + stderr to the app log file. Call once at process start
    /// — when launched via Finder there's no attached terminal, so `print` output
    /// goes nowhere unless we redirect.
    static func bootstrap() {
        freopen(appLogURL.path, "a+", stdout)
        freopen(appLogURL.path, "a+", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        log("app launched, pid=\(getpid())")
    }

    static func log(_ msg: String) {
        print("[\(Date())] \(msg)")
    }

    /// Returns a URL for a per-synthesis subprocess log file. Caller writes to it
    /// and surfaces it in the UI if synthesis fails.
    static func synthesisLogURL(id: String) -> URL {
        logsDir.appendingPathComponent("synthesis-\(id).log")
    }
}
```

- [ ] **Step 2: Wire `Logger.bootstrap()` into the app's init.**

Edit `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` — replace the `ScreenpipeFlowApp` struct with:

```swift
@main
struct ScreenpipeFlowApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Logger.bootstrap()
    }

    var body: some Scene {
        MenuBarExtra("ScreenpipeFlow", systemImage: "waveform.circle") {
            Text("ScreenpipeFlow").font(.headline)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 3: Run the app, verify logging works.**

```bash
swift run ScreenpipeFlow &
sleep 2
pkill -f ScreenpipeFlow
cat ~/Library/Logs/ScreenpipeFlow/app.log
```

Expected: a line like `[2026-05-12 14:32:01 +0000] app launched, pid=12345`.

- [ ] **Step 4: Commit.**

```bash
git add Sources/ScreenpipeFlow/Logger.swift Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "ScreenpipeFlow: file-based logger, mirroring Tool 1's pattern"
```

---

## Task 3: Slug derivation utility

**Files:**
- Create: `Sources/ScreenpipeFlow/Slug.swift`
- Create: `Tests/ScreenpipeFlowTests/SlugTests.swift`

Converts a human name or sentence into a kebab-case directory slug. Handles collisions by suffixing `-2`, `-3`, etc.

- [ ] **Step 1: Write the failing tests.**

Create `Tests/ScreenpipeFlowTests/SlugTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

final class SlugTests: XCTestCase {

    func testKebabCaseFromTitle() {
        XCTAssertEqual(Slug.derive(from: "Staging Signups Report"), "staging-signups-report")
    }

    func testStripsPunctuationAndCollapsesSpaces() {
        XCTAssertEqual(Slug.derive(from: "Hello, World!  Foo--bar"), "hello-world-foo-bar")
    }

    func testLeadingTrailingDashesRemoved() {
        XCTAssertEqual(Slug.derive(from: "  --weird-- "), "weird")
    }

    func testEmptyOrAllPunctuationFallsBackToDefault() {
        XCTAssertEqual(Slug.derive(from: ""), "untitled-flow")
        XCTAssertEqual(Slug.derive(from: "!!!"), "untitled-flow")
    }

    func testLongInputTruncatedTo60Chars() {
        let long = String(repeating: "a", count: 200)
        let slug = Slug.derive(from: long)
        XCTAssertLessThanOrEqual(slug.count, 60)
    }

    func testUniquifyAppendsSuffixWhenCollision() {
        let existing: Set<String> = ["check-prs", "check-prs-2"]
        XCTAssertEqual(Slug.uniquify("check-prs", existing: existing), "check-prs-3")
    }

    func testUniquifyReturnsOriginalWhenNoCollision() {
        XCTAssertEqual(Slug.uniquify("brand-new", existing: ["other"]), "brand-new")
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter SlugTests`
Expected: compile errors — `Slug` undefined.

- [ ] **Step 3: Implement `Slug`.**

Create `Sources/ScreenpipeFlow/Slug.swift`:

```swift
import Foundation

enum Slug {
    private static let maxLength = 60
    private static let fallback = "untitled-flow"

    static func derive(from input: String) -> String {
        let lower = input.lowercased()
        // Replace anything that isn't [a-z0-9] with a single dash.
        let scalars = lower.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber { return c }
            return "-"
        }
        var collapsed = String(scalars)
        // Collapse runs of dashes.
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.isEmpty { return fallback }
        if trimmed.count <= maxLength { return trimmed }
        let prefix = trimmed.prefix(maxLength)
        return String(prefix).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Returns a slug that does not collide with `existing` by appending -2, -3, …
    static func uniquify(_ slug: String, existing: Set<String>) -> String {
        if !existing.contains(slug) { return slug }
        var n = 2
        while existing.contains("\(slug)-\(n)") { n += 1 }
        return "\(slug)-\(n)"
    }
}
```

- [ ] **Step 4: Run the tests — verify they pass.**

Run: `swift test --filter SlugTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/Slug.swift Tests/ScreenpipeFlowTests/SlugTests.swift
git commit -m "Slug: name → kebab-case, collision suffixing (TDD)"
```

---

## Task 4: RecordingSession + SessionState

**Files:**
- Modify: `Sources/ScreenpipeFlow/AppState.swift` (move SessionState out)
- Create: `Sources/ScreenpipeFlow/RecordingSession.swift`
- Create: `Tests/ScreenpipeFlowTests/RecordingSessionTests.swift`

Defines the data shapes: `RecordingSession` (value type with mode, start times, end time), `SessionState` (the enum AppState holds), and `FlowEntry` (a library row).

- [ ] **Step 1: Write the failing tests.**

Create `Tests/ScreenpipeFlowTests/RecordingSessionTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

final class RecordingSessionTests: XCTestCase {

    func testProactiveSessionTimeRangeMatchesActiveStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var s = RecordingSession(mode: .proactive,
                                 bufferRangeStart: nil,
                                 activeRecordingStart: start)
        s.endTime = start.addingTimeInterval(45)
        XCTAssertEqual(s.timeRangeStart, start)
        XCTAssertEqual(s.timeRangeEnd, start.addingTimeInterval(45))
        XCTAssertEqual(s.durationSeconds, 45, accuracy: 0.01)
    }

    func testRetroactiveTimeRangeUsesBufferStart() {
        let bufferStart = Date(timeIntervalSince1970: 1_700_000_000)
        let activeStart = bufferStart.addingTimeInterval(300) // 5 min later
        var s = RecordingSession(mode: .retroactive,
                                 bufferRangeStart: bufferStart,
                                 activeRecordingStart: activeStart)
        s.endTime = activeStart.addingTimeInterval(60)
        XCTAssertEqual(s.timeRangeStart, bufferStart)
        XCTAssertEqual(s.timeRangeEnd, activeStart.addingTimeInterval(60))
        XCTAssertEqual(s.durationSeconds, 360, accuracy: 0.01) // 5 min buffer + 1 min active
    }

    func testFlowEntryEquality() {
        let url = URL(fileURLWithPath: "/tmp/foo")
        let date = Date()
        let a = FlowEntry(slug: "x", name: "X", path: url, createdAt: date)
        let b = FlowEntry(slug: "x", name: "X", path: url, createdAt: date)
        XCTAssertEqual(a, b)
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter RecordingSessionTests`
Expected: compile errors — types undefined.

- [ ] **Step 3: Implement `RecordingSession` and supporting types.**

Create `Sources/ScreenpipeFlow/RecordingSession.swift`:

```swift
import Foundation

enum RecordingMode: String, Codable, Equatable {
    case proactive
    case retroactive
}

struct RecordingSession: Equatable {
    let mode: RecordingMode
    /// Mode .retroactive only — earliest point grabbed from screenpipe's buffer.
    /// nil for .proactive.
    let bufferRangeStart: Date?
    /// When the user started narrating forward (clicked Start or Begin From Here).
    let activeRecordingStart: Date
    /// Set when the user clicks Stop. nil while still recording.
    var endTime: Date?

    /// The full time range to feed to the synthesizer. For .proactive this is
    /// [activeRecordingStart, endTime]; for .retroactive this is [bufferRangeStart, endTime].
    var timeRangeStart: Date {
        bufferRangeStart ?? activeRecordingStart
    }

    var timeRangeEnd: Date {
        endTime ?? Date()
    }

    var durationSeconds: TimeInterval {
        timeRangeEnd.timeIntervalSince(timeRangeStart)
    }
}

struct FlowEntry: Equatable, Identifiable {
    let slug: String
    let name: String
    let path: URL
    let createdAt: Date

    var id: String { slug }
}
```

- [ ] **Step 4: Update `AppState` to use the new `SessionState` enum referencing `RecordingSession`.**

Replace `Sources/ScreenpipeFlow/AppState.swift` entirely:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case browsingTimeline
        case recording(RecordingSession)
        case synthesizing(URL)        // path to manifest being processed
        case reviewing(URL)           // path to the synthesized skill directory
        case error(String)
    }

    private(set) var sessionState: SessionState = .idle
    private(set) var library: [FlowEntry] = []
}
```

- [ ] **Step 5: Run the tests — verify they pass.**

Run: `swift test --filter ScreenpipeFlowTests`
Expected: 8+ tests pass.

- [ ] **Step 6: Commit.**

```bash
git add Sources/ScreenpipeFlow/RecordingSession.swift Sources/ScreenpipeFlow/AppState.swift Tests/ScreenpipeFlowTests/RecordingSessionTests.swift
git commit -m "RecordingSession + FlowEntry + SessionState (TDD)"
```

---

## Task 5: ManifestWriter

**Files:**
- Create: `Sources/ScreenpipeFlow/ManifestWriter.swift`
- Create: `Tests/ScreenpipeFlowTests/ManifestWriterTests.swift`

Serializes a completed `RecordingSession` to a JSON manifest file. Schema documented in spec section "Manifest schema".

- [ ] **Step 1: Write the failing tests.**

Create `Tests/ScreenpipeFlowTests/ManifestWriterTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

final class ManifestWriterTests: XCTestCase {

    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manifest-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testProactiveManifestStructure() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: start)
        session.endTime = start.addingTimeInterval(60)

        let manifestURL = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/Users/test/.claude/skills"),
            userHintsName: nil,
            userHintsDescription: nil,
            userHintsNotes: nil,
            regenerationContext: nil,
            manifestsDir: tmpDir
        )

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        XCTAssertEqual(json["manifestVersion"] as? Int, 1)
        XCTAssertEqual(json["mode"] as? String, "proactive")
        XCTAssertNotNil(json["manifestId"])
        XCTAssertEqual(json["outputDir"] as? String, "/Users/test/.claude/skills")
        XCTAssertNil(json["regenerationContext"] as? [String: Any])
        let timeRange = json["timeRange"] as? [String: Any]
        XCTAssertEqual(timeRange?["start"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(timeRange?["end"] as? String, "2023-11-14T22:14:20Z")
        XCTAssertEqual(json["activeRecordingStart"] as? String, "2023-11-14T22:13:20Z")
    }

    func testRetroactiveManifestHasBufferStart() throws {
        let bufferStart = Date(timeIntervalSince1970: 1_700_000_000)
        let activeStart = bufferStart.addingTimeInterval(300)
        var session = RecordingSession(mode: .retroactive,
                                       bufferRangeStart: bufferStart,
                                       activeRecordingStart: activeStart)
        session.endTime = activeStart.addingTimeInterval(60)

        let manifestURL = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/Users/test/.claude/skills"),
            userHintsName: "Weekly Report",
            userHintsDescription: nil,
            userHintsNotes: nil,
            regenerationContext: nil,
            manifestsDir: tmpDir
        )

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        XCTAssertEqual(json["mode"] as? String, "retroactive")
        let timeRange = json["timeRange"] as? [String: Any]
        XCTAssertEqual(timeRange?["start"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["activeRecordingStart"] as? String, "2023-11-14T22:18:20Z")
        let hints = json["userHints"] as? [String: Any]
        XCTAssertEqual(hints?["name"] as? String, "Weekly Report")
    }

    func testRegenerationContextSerializes() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: start)
        session.endTime = start.addingTimeInterval(30)

        let regen = ManifestWriter.RegenerationContext(
            previousSkillPath: URL(fileURLWithPath: "/Users/test/.claude/skills/foo"),
            userFeedback: "Rename it to bar"
        )

        let manifestURL = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/Users/test/.claude/skills"),
            userHintsName: nil,
            userHintsDescription: nil,
            userHintsNotes: nil,
            regenerationContext: regen,
            manifestsDir: tmpDir
        )

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        let ctx = json["regenerationContext"] as? [String: Any]
        XCTAssertEqual(ctx?["previousSkillPath"] as? String, "/Users/test/.claude/skills/foo")
        XCTAssertEqual(ctx?["userFeedback"] as? String, "Rename it to bar")
    }

    func testManifestFilenameIsUUIDJson() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: start)
        session.endTime = start.addingTimeInterval(10)
        let url = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/x"),
            userHintsName: nil,
            userHintsDescription: nil,
            userHintsNotes: nil,
            regenerationContext: nil,
            manifestsDir: tmpDir
        )
        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent.count, 36) // UUID length
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter ManifestWriterTests`
Expected: compile errors — `ManifestWriter` undefined.

- [ ] **Step 3: Implement `ManifestWriter`.**

Create `Sources/ScreenpipeFlow/ManifestWriter.swift`:

```swift
import Foundation

enum ManifestWriter {
    struct RegenerationContext: Encodable {
        let previousSkillPath: URL
        let userFeedback: String

        enum CodingKeys: String, CodingKey {
            case previousSkillPath, userFeedback
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(previousSkillPath.path, forKey: .previousSkillPath)
            try c.encode(userFeedback, forKey: .userFeedback)
        }
    }

    enum WriteError: Error {
        case sessionNotEnded
    }

    /// Writes a manifest JSON to `<manifestsDir>/<uuid>.json` and returns its URL.
    /// Caller is responsible for creating `manifestsDir` if it doesn't exist.
    @MainActor
    static func write(
        session: RecordingSession,
        outputDir: URL,
        userHintsName: String?,
        userHintsDescription: String?,
        userHintsNotes: String?,
        regenerationContext: RegenerationContext?,
        manifestsDir: URL
    ) throws -> URL {
        guard let _ = session.endTime else {
            throw WriteError.sessionNotEnded
        }
        try FileManager.default.createDirectory(at: manifestsDir, withIntermediateDirectories: true)

        let manifestId = UUID().uuidString
        let url = manifestsDir.appendingPathComponent("\(manifestId).json")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var dict: [String: Any] = [
            "manifestVersion": 1,
            "manifestId": manifestId,
            "createdAt": iso.string(from: Date()),
            "mode": session.mode.rawValue,
            "timeRange": [
                "start": iso.string(from: session.timeRangeStart),
                "end": iso.string(from: session.timeRangeEnd)
            ],
            "activeRecordingStart": iso.string(from: session.activeRecordingStart),
            "userHints": [
                "name": userHintsName as Any,
                "description": userHintsDescription as Any,
                "notes": userHintsNotes as Any
            ],
            "outputDir": outputDir.path,
            "regenerationContext": NSNull()
        ]
        if let regen = regenerationContext {
            dict["regenerationContext"] = [
                "previousSkillPath": regen.previousSkillPath.path,
                "userFeedback": regen.userFeedback
            ]
        }

        let data = try JSONSerialization.data(withJSONObject: dict,
                                              options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        return url
    }
}
```

- [ ] **Step 4: Run the tests — verify they pass.**

Run: `swift test --filter ManifestWriterTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/ManifestWriter.swift Tests/ScreenpipeFlowTests/ManifestWriterTests.swift
git commit -m "ManifestWriter: JSON manifest serialization, all mode/regen variants (TDD)"
```

---

## Task 6: ScreenpipeClient — health + audio status

**Files:**
- Create: `Sources/ScreenpipeFlow/ScreenpipeClient.swift`
- Create: `Tests/ScreenpipeFlowTests/ScreenpipeClientTests.swift`

Thin async HTTP wrapper over `http://127.0.0.1:3030`. First slice: `/health` (returns overall status + audio status). Used by RecordingController to preflight.

- [ ] **Step 1: Write the failing tests using fixture responses.**

Create `Tests/ScreenpipeFlowTests/ScreenpipeClientTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

final class ScreenpipeClientTests: XCTestCase {

    func testHealthParsesRunningAudio() throws {
        let payload = """
        {
          "status": "healthy",
          "frame_status": "ok",
          "audio_status": "ok",
          "ui_status": "ok",
          "last_frame_timestamp": "2026-05-12T14:30:00Z"
        }
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertTrue(health.isHealthy)
        XCTAssertEqual(health.audioStatus, .running)
    }

    func testHealthParsesPausedAudio() throws {
        let payload = """
        {"status":"healthy","frame_status":"ok","audio_status":"paused","ui_status":"ok"}
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertEqual(health.audioStatus, .paused)
    }

    func testHealthParsesUnknownAudioStatus() throws {
        let payload = """
        {"status":"healthy","frame_status":"ok","audio_status":"weird_value","ui_status":"ok"}
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertEqual(health.audioStatus, .unknown)
    }

    func testHealthParsesUnhealthy() throws {
        let payload = """
        {"status":"error","frame_status":"err","audio_status":"err","ui_status":"err"}
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertFalse(health.isHealthy)
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter ScreenpipeClientTests`
Expected: compile errors — `ScreenpipeClient` undefined.

- [ ] **Step 3: Implement `ScreenpipeClient`.**

Create `Sources/ScreenpipeFlow/ScreenpipeClient.swift`:

```swift
import Foundation

actor ScreenpipeClient {
    struct Health {
        let isHealthy: Bool
        let audioStatus: AudioStatus
    }

    enum AudioStatus: String {
        case running     // screenpipe reports "ok" / "running"
        case paused
        case unknown     // unrecognized value — assume bad, prompt user
    }

    enum ClientError: Error, LocalizedError {
        case notRunning
        case decode(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notRunning: return "screenpipe is not running on 127.0.0.1:3030"
            case .decode(let s): return "screenpipe response malformed: \(s)"
            case .http(let code): return "screenpipe returned HTTP \(code)"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:3030")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> Health {
        let url = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        let (data, response) = try await dataOrConnectErr(req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.parseHealth(data)
    }

    /// Pure parsing logic — testable without network.
    static func parseHealth(_ data: Data) throws -> Health {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.decode("not a JSON object")
        }
        let status = (json["status"] as? String) ?? ""
        let audio = (json["audio_status"] as? String) ?? ""
        let isHealthy = status == "healthy"
        let audioStatus: AudioStatus = {
            switch audio.lowercased() {
            case "ok", "running": return .running
            case "paused": return .paused
            default: return .unknown
            }
        }()
        return Health(isHealthy: isHealthy, audioStatus: audioStatus)
    }

    private func dataOrConnectErr(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch let err as URLError where err.code == .cannotConnectToHost || err.code == .timedOut {
            throw ClientError.notRunning
        }
    }
}
```

- [ ] **Step 4: Run the tests — verify they pass.**

Run: `swift test --filter ScreenpipeClientTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/ScreenpipeClient.swift Tests/ScreenpipeFlowTests/ScreenpipeClientTests.swift
git commit -m "ScreenpipeClient: health + audio status parsing (TDD)"
```

---

## Task 7: ScreenpipeClient — frame thumbnails for Timeline window

**Files:**
- Modify: `Sources/ScreenpipeFlow/ScreenpipeClient.swift`
- Modify: `Tests/ScreenpipeFlowTests/ScreenpipeClientTests.swift`

Adds a method that returns a list of frame timestamps (and per-frame app names) over a time range — used by `TimelineWindow` to build the thumbnail strip in Mode C.

Screenpipe's search endpoint: `GET /search?content_type=ocr&start_time=ISO8601&end_time=ISO8601&limit=N`. We use `ocr` (which carries frame metadata: timestamp, app name) instead of fetching pixel frames at preview time — much faster.

- [ ] **Step 1: Write failing tests for the new method's parsing logic.**

Append to `Tests/ScreenpipeFlowTests/ScreenpipeClientTests.swift`:

```swift
extension ScreenpipeClientTests {

    func testThumbnailIndexParsesOCRResults() throws {
        let payload = """
        {
          "data": [
            {"type":"OCR","content":{"timestamp":"2026-05-12T14:25:00Z","app_name":"Google Chrome","window_name":"Dashboard"}},
            {"type":"OCR","content":{"timestamp":"2026-05-12T14:27:00Z","app_name":"Slack","window_name":"#growth"}},
            {"type":"OCR","content":{"timestamp":"2026-05-12T14:29:00Z","app_name":"Slack","window_name":"#growth"}}
          ]
        }
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].appName, "Google Chrome")
        XCTAssertEqual(items[1].appName, "Slack")
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(items[0].timestamp, iso.date(from: "2026-05-12T14:25:00Z"))
    }

    func testThumbnailIndexHandlesEmptyResults() throws {
        let payload = """
        {"data":[]}
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items, [])
    }

    func testThumbnailIndexSkipsNonOCREntries() throws {
        let payload = """
        {"data":[
          {"type":"OCR","content":{"timestamp":"2026-05-12T14:25:00Z","app_name":"Chrome","window_name":""}},
          {"type":"Audio","content":{"timestamp":"2026-05-12T14:26:00Z","transcription":"hi"}}
        ]}
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items.count, 1)
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter ScreenpipeClientTests`
Expected: 3 new failures — `parseThumbnailIndex` undefined, `ThumbnailItem` undefined.

- [ ] **Step 3: Extend `ScreenpipeClient`.**

Add to `Sources/ScreenpipeFlow/ScreenpipeClient.swift` (inside the actor):

```swift
    struct ThumbnailItem: Equatable {
        let timestamp: Date
        let appName: String
        let windowName: String
    }

    /// Returns thumbnail-index items over a time range, sorted oldest first.
    /// We don't pull pixel data here — too slow for an interactive preview strip.
    /// The Timeline window fetches frame pixels lazily for the visible subset.
    func thumbnailIndex(from start: Date,
                       to end: Date,
                       limit: Int = 200) async throws -> [ThumbnailItem] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var components = URLComponents(url: baseURL.appendingPathComponent("search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "content_type", value: "ocr"),
            URLQueryItem(name: "start_time", value: iso.string(from: start)),
            URLQueryItem(name: "end_time", value: iso.string(from: end)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        var req = URLRequest(url: components.url!)
        req.timeoutInterval = 10
        let (data, response) = try await dataOrConnectErr(req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.parseThumbnailIndex(data)
    }

    static func parseThumbnailIndex(_ data: Data) throws -> [ThumbnailItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw ClientError.decode("expected {data: [...]}")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var items: [ThumbnailItem] = []
        for entry in arr {
            guard (entry["type"] as? String) == "OCR",
                  let content = entry["content"] as? [String: Any],
                  let ts = content["timestamp"] as? String,
                  let date = iso.date(from: ts) else {
                continue
            }
            let app = (content["app_name"] as? String) ?? ""
            let window = (content["window_name"] as? String) ?? ""
            items.append(ThumbnailItem(timestamp: date, appName: app, windowName: window))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }
```

- [ ] **Step 4: Run the tests — verify they pass.**

Run: `swift test --filter ScreenpipeClientTests`
Expected: 7 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/ScreenpipeClient.swift Tests/ScreenpipeFlowTests/ScreenpipeClientTests.swift
git commit -m "ScreenpipeClient: thumbnail index for Timeline window (TDD)"
```

---

## Task 8: SynthesisRunner — subprocess wrapper

**Files:**
- Create: `Sources/ScreenpipeFlow/SynthesisRunner.swift`
- Create: `Tests/ScreenpipeFlowTests/SynthesisRunnerTests.swift`

Spawns a configurable command (in production, `claude -p`) with a manifest path, captures stdout/stderr to a log file, and parses the final JSON status line. The runner is generic over the command so tests can use a stub script.

- [ ] **Step 1: Write the failing tests.**

Create `Tests/ScreenpipeFlowTests/SynthesisRunnerTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

final class SynthesisRunnerTests: XCTestCase {

    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("synth-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Writes a small bash script that emulates `claude -p` for testing.
    private func writeFakeClaude(printingFinalLine line: String,
                                  exitCode: Int32 = 0) throws -> URL {
        let script = """
        #!/bin/bash
        echo "fake-claude started, args: $@"
        echo "some intermediate output"
        echo '\(line)'
        exit \(exitCode)
        """
        let url = tmpDir.appendingPathComponent("fake-claude.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
        return url
    }

    func testParsesSuccessStatusLine() async throws {
        let claude = try writeFakeClaude(
            printingFinalLine: #"{"status":"ok","outputDir":"/tmp/skills/foo","slug":"foo"}"#)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: ["-p", "prompt", manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .success(let dir, let slug) = result {
            XCTAssertEqual(dir, URL(fileURLWithPath: "/tmp/skills/foo"))
            XCTAssertEqual(slug, "foo")
        } else {
            XCTFail("expected .success, got \(result)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testParsesFailureStatusLine() async throws {
        let claude = try writeFakeClaude(
            printingFinalLine: #"{"status":"error","message":"no narration detected"}"#)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: [manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .failure(let msg) = result {
            XCTAssertTrue(msg.contains("no narration detected"))
        } else {
            XCTFail("expected .failure, got \(result)")
        }
    }

    func testFailsWhenNoStatusLineFound() async throws {
        let claude = try writeFakeClaude(printingFinalLine: "no json here")
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: [manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .failure = result { /* ok */ } else {
            XCTFail("expected .failure, got \(result)")
        }
    }

    func testFailsOnNonZeroExit() async throws {
        let claude = try writeFakeClaude(printingFinalLine: "anything", exitCode: 1)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: [manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .failure = result { /* ok */ } else {
            XCTFail("expected .failure, got \(result)")
        }
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter SynthesisRunnerTests`
Expected: compile errors — `SynthesisRunner` undefined.

- [ ] **Step 3: Implement `SynthesisRunner`.**

Create `Sources/ScreenpipeFlow/SynthesisRunner.swift`:

```swift
import Foundation

enum SynthesisResult: Equatable {
    case success(outputDir: URL, slug: String)
    case failure(message: String)
}

enum SynthesisRunner {

    enum RunError: Error, LocalizedError {
        case timeout
        case spawnFailed(String)

        var errorDescription: String? {
            switch self {
            case .timeout: return "Synthesis subprocess timed out"
            case .spawnFailed(let s): return "Failed to spawn synthesis subprocess: \(s)"
            }
        }
    }

    /// Spawns `command` with `arguments`, captures all output to `logFile`, and
    /// parses the LAST line of stdout matching the success/failure JSON contract.
    /// Returns .success or .failure. Throws on timeout or spawn failure.
    static func run(
        command: URL,
        arguments: [String],
        logFile: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> SynthesisResult {
        try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFile)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = command
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        var capturedStdout = Data()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            capturedStdout.append(chunk)
            try? logHandle.write(contentsOf: chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            try? logHandle.write(contentsOf: chunk)
        }

        do {
            try process.run()
        } catch {
            throw RunError.spawnFailed("\(error)")
        }

        // Race the process against the timeout.
        let processTask = Task.detached(priority: .userInitiated) { @Sendable in
            process.waitUntilExit()
        }
        let timeoutTask = Task.detached(priority: .background) { @Sendable in
            try await Task.sleep(for: .seconds(timeoutSeconds))
            if process.isRunning { process.terminate() }
        }
        await processTask.value
        timeoutTask.cancel()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain any final buffered bytes.
        if let rest = try? stdoutPipe.fileHandleForReading.readToEnd() {
            capturedStdout.append(rest)
            try? logHandle.write(contentsOf: rest)
        }
        if let rest = try? stderrPipe.fileHandleForReading.readToEnd() {
            try? logHandle.write(contentsOf: rest)
        }

        if process.terminationStatus != 0 {
            return .failure(message: "subprocess exited with status \(process.terminationStatus)")
        }

        return parseLastStatusLine(stdout: capturedStdout)
    }

    /// Visible for testing.
    static func parseLastStatusLine(stdout: Data) -> SynthesisResult {
        guard let text = String(data: stdout, encoding: .utf8) else {
            return .failure(message: "subprocess stdout was not valid UTF-8")
        }
        // Walk from the end, find the last line that parses as a JSON object with "status".
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                continue
            }
            if status == "ok" {
                let dir = (json["outputDir"] as? String).map { URL(fileURLWithPath: $0) }
                let slug = json["slug"] as? String
                if let dir = dir, let slug = slug {
                    return .success(outputDir: dir, slug: slug)
                }
                return .failure(message: "status=ok but missing outputDir/slug")
            } else {
                let msg = (json["message"] as? String) ?? "unknown error"
                return .failure(message: msg)
            }
        }
        return .failure(message: "no {\"status\":...} JSON line found in subprocess stdout")
    }
}
```

- [ ] **Step 4: Run the tests — verify they pass.**

Run: `swift test --filter SynthesisRunnerTests`
Expected: 4 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/SynthesisRunner.swift Tests/ScreenpipeFlowTests/SynthesisRunnerTests.swift
git commit -m "SynthesisRunner: subprocess + status-line parsing (TDD)"
```

---

## Task 9: Bootstrap synthesis prompt resource

**Files:**
- Create: `Resources/synthesis-prompt.md`
- Modify: `Package.swift` (declare Resources for ScreenpipeFlow)

The prompt that gets passed to `claude -p`. Loaded at runtime from `Bundle.main` so it can be iterated independently of the Swift code.

- [ ] **Step 1: Create the prompt file.**

Create `Resources/synthesis-prompt.md`:

```markdown
You are synthesizing a Claude Code skill from a recorded user demonstration.

The user demonstrated a task on their Mac, narrating aloud what they were
doing so it could be captured as a reusable skill. Convert the recording
into a Claude Code skill directory.

INPUTS:
  - Manifest at: $MANIFEST_PATH
  - The screenpipe MCP tools (mcp__screenpipe__*) for querying the recording.
    If those tools are unavailable, fall back to the HTTP API at
    http://127.0.0.1:3030 (use the Bash tool to curl /search and /audio).

PROCESS:
  1. Read $MANIFEST_PATH. Note timeRange and activeRecordingStart.
  2. Fetch over the time range:
     - Audio transcript (user narration) — primary source of truth for INTENT
     - OCR text + accessibility events — grounding evidence
     - 5-15 key screenshots at semantic boundaries (app switch, click, scroll burst)
  3. NARRATION IS PRIMARY. If the user says "log into the staging dashboard"
     and opens dashboard.example.com, encode the intent as "log into the
     staging dashboard" — not "navigate to a specific URL". The URL is just
     evidence.
  4. PARAMETER DETECTION: scan narration for variable callouts. Phrases like
     "that's a variable", "call this X", "this part is different each time",
     "my email is X — treat as a parameter" all become entries in the
     parameters list. Replace concrete values with {{param_name}} in
     SKILL.md and flow.json. Also auto-detect obvious parameters (account
     names, emails, file paths) even without explicit callout, but mark them
     "autoDetected": true so the user can confirm or reject in Review.
  5. MODE "retroactive": [timeRange.start, activeRecordingStart) is pre-
     narration. Reconstruct those steps from screen + accessibility alone.
     Tag each such flow.json step with "inferred": true. Add a note at the
     top of SKILL.md flagging those steps for verification. If the user
     narrates retrospectively ("earlier I was opening the dashboard"),
     align that narration with the corresponding past frames.
  6. SLUG: derive from userHints.name if present, else from intent. kebab-case.

OUTPUT to <outputDir>/<slug>/:
  - SKILL.md       (frontmatter `name`, `description`; body sections:
                    `## Intent`, `## Parameters`, `## Steps`)
  - flow.json      (schemaVersion 1; see spec for full schema)
  - frames/*.png   (key screenshots; reference by relative path)

REGENERATION:
  If $MANIFEST_PATH includes a `regenerationContext` field, you are
  regenerating an existing skill. Apply the userFeedback to the new
  output; delete and replace the previousSkillPath atomically.

ON SUCCESS, print exactly one final line to stdout (and nothing after it):
  {"status":"ok","outputDir":"<absolute path>","slug":"<slug>"}
ON FAILURE, print exactly one final line:
  {"status":"error","message":"<one-line reason>"}
```

- [ ] **Step 2: Update `Package.swift` to bundle the Resources directory for ScreenpipeFlow.**

Replace the ScreenpipeFlow target declaration with:

```swift
        .executableTarget(
            name: "ScreenpipeFlow",
            path: "Sources/ScreenpipeFlow",
            resources: [
                .copy("../../Resources/synthesis-prompt.md")
            ]
        ),
```

(SwiftPM lets a target reference resources outside its own path via `..` — verified pattern.)

- [ ] **Step 3: Smoke-test that the bundle picks up the resource.**

Add a temporary print statement in `ScreenpipeFlowApp.init`:

```swift
        let resURL = Bundle.module.url(forResource: "synthesis-prompt", withExtension: "md")
        Logger.log("synthesis-prompt resource URL: \(resURL?.path ?? "nil")")
```

(Note: SwiftPM auto-generates `Bundle.module` for targets with declared resources.)

Run: `swift run ScreenpipeFlow &; sleep 2; pkill -f ScreenpipeFlow; tail -1 ~/Library/Logs/ScreenpipeFlow/app.log`
Expected: a non-`nil` path to a `synthesis-prompt.md` inside the build product's bundle.

- [ ] **Step 4: Remove the temporary print.**

Revert the `ScreenpipeFlowApp.init` change. (Resource will be accessed for real in Task 12.)

- [ ] **Step 5: Commit.**

```bash
git add Resources/synthesis-prompt.md Package.swift
git commit -m "synthesis-prompt.md: bootstrap prompt resource, bundled into app"
```

---

## Task 10: HotkeyManager

**Files:**
- Create: `Sources/ScreenpipeFlow/HotkeyManager.swift`

Global hotkey registration via Carbon. No XCTest — Carbon hotkeys require a real event loop and aren't unit-testable in a clean way. Verified by manual smoke test at the end of the task.

- [ ] **Step 1: Implement `HotkeyManager`.**

Create `Sources/ScreenpipeFlow/HotkeyManager.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's RegisterEventHotKey to install a process-wide global hotkey.
/// macOS requires Accessibility permission for some global hotkey combinations;
/// the user is prompted on first registration if needed.
@MainActor
final class HotkeyManager {
    struct Binding {
        /// Carbon virtual key code (e.g. kVK_ANSI_R == 15).
        let keyCode: UInt32
        /// Carbon modifier mask (cmdKey, optionKey, controlKey, shiftKey).
        let modifiers: UInt32
    }

    static let recordToggle = Binding(
        keyCode: UInt32(kVK_ANSI_R),
        modifiers: UInt32(controlKey | optionKey)
    )
    static let grabLast = Binding(
        keyCode: UInt32(kVK_ANSI_G),
        modifiers: UInt32(controlKey | optionKey)
    )

    private var registered: [(EventHotKeyRef, () -> Void)] = []
    private var eventHandlerRef: EventHandlerRef?

    init() {
        installHandler()
    }

    deinit {
        for (ref, _) in registered { UnregisterEventHotKey(ref) }
        if let h = eventHandlerRef { RemoveEventHandler(h) }
    }

    func register(_ binding: Binding, action: @escaping () -> Void) {
        var hkRef: EventHotKeyRef?
        var hkID = EventHotKeyID(signature: OSType(0x53464C57), // "SFLW"
                                  id: UInt32(registered.count + 1))
        let status = RegisterEventHotKey(binding.keyCode,
                                          binding.modifiers,
                                          hkID,
                                          GetApplicationEventTarget(),
                                          0,
                                          &hkRef)
        if status != noErr {
            Logger.log("hotkey registration failed: status=\(status)")
            return
        }
        if let ref = hkRef {
            registered.append((ref, action))
        }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
                            { (_, eventRef, userData) -> OSStatus in
                                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                                var hkID = EventHotKeyID()
                                let status = GetEventParameter(eventRef,
                                                                EventParamName(kEventParamDirectObject),
                                                                EventParamType(typeEventHotKeyID),
                                                                nil,
                                                                MemoryLayout<EventHotKeyID>.size,
                                                                nil,
                                                                &hkID)
                                guard status == noErr else { return status }
                                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                                let idx = Int(hkID.id) - 1
                                if idx >= 0, idx < manager.registered.count {
                                    DispatchQueue.main.async { manager.registered[idx].1() }
                                }
                                return noErr
                            },
                            1,
                            &eventType,
                            selfPtr,
                            &eventHandlerRef)
    }
}
```

- [ ] **Step 2: Smoke-test in `ScreenpipeFlowApp` — temporarily wire a test hotkey.**

Edit `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`. Replace the `ScreenpipeFlowApp` body with:

```swift
@main
struct ScreenpipeFlowApp: App {
    @State private var appState = AppState()
    @State private var hotkeys = HotkeyManager()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Logger.bootstrap()
    }

    var body: some Scene {
        MenuBarExtra("ScreenpipeFlow", systemImage: "waveform.circle") {
            Text("ScreenpipeFlow").font(.headline)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
        .onChange(of: appState.sessionState) { _, _ in }
    }
}
```

Then add a temporary registration in `init`:

```swift
    init() {
        Logger.bootstrap()
        // SMOKE TEST — removed in next step
        Task { @MainActor in
            HotkeyManager.shared?.register(HotkeyManager.recordToggle) {
                Logger.log("⌃⌥R fired")
            }
        }
    }
```

This won't compile yet — `HotkeyManager.shared` doesn't exist. The simplest smoke test is harder than expected. **Skip the smoke test for now**; the hotkey wiring will be exercised by Task 12 (RecordingController). Revert the `init` change.

- [ ] **Step 3: Commit.**

```bash
git add Sources/ScreenpipeFlow/HotkeyManager.swift
git commit -m "HotkeyManager: Carbon-backed global hotkey wrapper"
```

---

## Task 11: AppState — wire screenpipe status polling + library loading

**Files:**
- Modify: `Sources/ScreenpipeFlow/AppState.swift`
- Modify: `Tests/ScreenpipeFlowTests/AppStateTests.swift`

`AppState` grows from placeholder to real orchestrator. Holds the session-state machine, the in-memory library of created flows, and a polled `screenpipeStatus`. Methods to transition between states are exposed for `RecordingController` to call.

- [ ] **Step 1: Write the failing tests for state transitions.**

Replace `Tests/ScreenpipeFlowTests/AppStateTests.swift`:

```swift
import XCTest
@testable import ScreenpipeFlow

@MainActor
final class AppStateTests: XCTestCase {

    func testInitialStateIsIdle() {
        let state = AppState()
        if case .idle = state.sessionState { return }
        XCTFail("expected .idle, got \(state.sessionState)")
    }

    func testTransitionToBrowsingTimeline() {
        let state = AppState()
        state.beginBrowsingTimeline()
        if case .browsingTimeline = state.sessionState { return }
        XCTFail("expected .browsingTimeline, got \(state.sessionState)")
    }

    func testTransitionToRecordingFromIdle() {
        let state = AppState()
        let session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
        if case .recording = state.sessionState { return }
        XCTFail("expected .recording, got \(state.sessionState)")
    }

    func testTransitionToSynthesizing() {
        let state = AppState()
        let session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
        let url = URL(fileURLWithPath: "/tmp/manifest.json")
        state.beginSynthesizing(manifest: url)
        if case .synthesizing(let m) = state.sessionState {
            XCTAssertEqual(m, url)
        } else {
            XCTFail("expected .synthesizing")
        }
    }

    func testReturnToIdleAfterSave() {
        let state = AppState()
        let session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
        state.beginSynthesizing(manifest: URL(fileURLWithPath: "/tmp/m.json"))
        state.beginReviewing(skill: URL(fileURLWithPath: "/tmp/skill"))
        state.finalize()
        if case .idle = state.sessionState { return }
        XCTFail("expected .idle after finalize, got \(state.sessionState)")
    }

    func testAddFlowEntryAppendsToLibrary() {
        let state = AppState()
        let entry = FlowEntry(slug: "foo",
                              name: "Foo",
                              path: URL(fileURLWithPath: "/tmp/foo"),
                              createdAt: Date())
        state.addFlow(entry)
        XCTAssertEqual(state.library.count, 1)
        XCTAssertEqual(state.library.first?.slug, "foo")
    }
}
```

- [ ] **Step 2: Run the tests — verify they fail.**

Run: `swift test --filter AppStateTests`
Expected: 5 new tests fail with "no method" errors.

- [ ] **Step 3: Expand `AppState` with the transition methods + library mutations.**

Replace `Sources/ScreenpipeFlow/AppState.swift`:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case browsingTimeline
        case recording(RecordingSession)
        case synthesizing(URL)        // manifest path
        case reviewing(URL)           // skill directory path
        case error(String)
    }

    enum ScreenpipeStatus: Equatable {
        case unknown
        case running
        case audioPaused
        case unhealthy(String)
    }

    private(set) var sessionState: SessionState = .idle
    private(set) var library: [FlowEntry] = []
    private(set) var screenpipeStatus: ScreenpipeStatus = .unknown

    // MARK: - Session transitions

    func beginBrowsingTimeline() {
        sessionState = .browsingTimeline
    }

    func cancelBrowsingTimeline() {
        sessionState = .idle
    }

    func beginRecording(_ session: RecordingSession) {
        sessionState = .recording(session)
    }

    func beginSynthesizing(manifest: URL) {
        sessionState = .synthesizing(manifest)
    }

    func beginReviewing(skill: URL) {
        sessionState = .reviewing(skill)
    }

    func setError(_ message: String) {
        sessionState = .error(message)
    }

    /// Returns to `.idle` — call after a successful save, discard, or error dismissal.
    func finalize() {
        sessionState = .idle
    }

    // MARK: - Library

    func addFlow(_ entry: FlowEntry) {
        library.append(entry)
        library.sort { $0.createdAt > $1.createdAt }
    }

    func removeFlow(slug: String) {
        library.removeAll { $0.slug == slug }
    }

    // MARK: - screenpipe status

    func updateScreenpipeStatus(_ status: ScreenpipeStatus) {
        screenpipeStatus = status
    }
}
```

- [ ] **Step 4: Run the tests — verify they pass.**

Run: `swift test --filter AppStateTests`
Expected: 6 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/AppState.swift Tests/ScreenpipeFlowTests/AppStateTests.swift
git commit -m "AppState: state machine + library + screenpipe status (TDD)"
```

---

## Task 12: RecordingController — preflight + start/stop orchestration

**Files:**
- Create: `Sources/ScreenpipeFlow/RecordingController.swift`

The glue layer. `RecordingController` is the only place that knows: how to verify preflight conditions, how to write a manifest, how to spawn the synthesizer, and how to drive `AppState` through the recording → synthesizing → reviewing transitions. Other components (menu UI, HUD, Timeline) call into it.

No unit tests for this task — its job is integration, exercised by the manual smoke-test checklist (Task 22). Internal logic is delegated to already-tested types.

- [ ] **Step 1: Implement `RecordingController`.**

Create `Sources/ScreenpipeFlow/RecordingController.swift`:

```swift
import Foundation
import AppKit

@MainActor
final class RecordingController {
    private let state: AppState
    private let client: ScreenpipeClient
    private let manifestsDir: URL
    private let outputDir: URL
    private let synthesisPrompt: String
    private let claudeExecutable: URL?

    init(state: AppState) {
        self.state = state
        self.client = ScreenpipeClient()
        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScreenpipeFlow", isDirectory: true)
        self.manifestsDir = appSupport.appendingPathComponent("manifests", isDirectory: true)
        self.outputDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
        self.synthesisPrompt = Self.loadSynthesisPrompt()
        self.claudeExecutable = Self.findClaude()
        try? FileManager.default.createDirectory(at: manifestsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
    }

    private static func loadSynthesisPrompt() -> String {
        if let url = Bundle.module.url(forResource: "synthesis-prompt", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        Logger.log("WARNING: synthesis-prompt.md not found in bundle")
        return "Synthesize a Claude Code skill from the manifest at $MANIFEST_PATH."
    }

    private static func findClaude() -> URL? {
        let candidates = ["/usr/local/bin/claude",
                          "/opt/homebrew/bin/claude",
                          NSHomeDirectory() + "/.claude/local/claude",
                          NSHomeDirectory() + "/.npm-global/bin/claude"]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    // MARK: - Preflight

    enum PreflightFailure {
        case screenpipeNotRunning
        case audioPaused
        case claudeNotFound
    }

    func preflight() async -> PreflightFailure? {
        do {
            let health = try await client.health()
            if !health.isHealthy {
                return .screenpipeNotRunning
            }
            if health.audioStatus == .paused {
                return .audioPaused
            }
        } catch {
            return .screenpipeNotRunning
        }
        if claudeExecutable == nil {
            return .claudeNotFound
        }
        return nil
    }

    // MARK: - Lifecycle

    func startProactive() async {
        if let failure = await preflight() {
            showPreflightDialog(failure)
            return
        }
        let session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
    }

    func startRetroactive(bufferStart: Date) async {
        if let failure = await preflight() {
            showPreflightDialog(failure)
            return
        }
        let session = RecordingSession(mode: .retroactive,
                                       bufferRangeStart: bufferStart,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
    }

    func stop() async {
        guard case .recording(var session) = state.sessionState else { return }
        session.endTime = Date()
        if session.durationSeconds < 10 {
            state.finalize()
            showAlert(title: "Recording too short", message: "Synthesize a longer demonstration (>10 s).")
            return
        }
        await runSynthesis(for: session, regen: nil)
    }

    func regenerate(previousSkillPath: URL, userFeedback: String, originalSession: RecordingSession) async {
        let regen = ManifestWriter.RegenerationContext(
            previousSkillPath: previousSkillPath,
            userFeedback: userFeedback)
        await runSynthesis(for: originalSession, regen: regen)
    }

    // MARK: - Synthesis

    private func runSynthesis(for session: RecordingSession,
                              regen: ManifestWriter.RegenerationContext?) async {
        let manifestURL: URL
        do {
            manifestURL = try ManifestWriter.write(
                session: session,
                outputDir: outputDir,
                userHintsName: nil,
                userHintsDescription: nil,
                userHintsNotes: nil,
                regenerationContext: regen,
                manifestsDir: manifestsDir)
        } catch {
            state.setError("Failed to write manifest: \(error)")
            return
        }
        state.beginSynthesizing(manifest: manifestURL)

        guard let claude = claudeExecutable else {
            state.setError("Claude Code CLI not found")
            return
        }
        let logURL = Logger.synthesisLogURL(id: UUID().uuidString)
        let prompt = synthesisPrompt.replacingOccurrences(of: "$MANIFEST_PATH", with: manifestURL.path)

        do {
            let result = try await SynthesisRunner.run(
                command: claude,
                arguments: ["-p", prompt],
                logFile: logURL,
                timeoutSeconds: 300)
            switch result {
            case .success(let dir, let slug):
                let entry = FlowEntry(slug: slug,
                                      name: slug,
                                      path: dir,
                                      createdAt: Date())
                state.addFlow(entry)
                state.beginReviewing(skill: dir)
            case .failure(let message):
                state.setError("Synthesis failed: \(message). Log: \(logURL.path)")
            }
        } catch {
            state.setError("Synthesis subprocess error: \(error)")
        }
    }

    // MARK: - UI helpers (NSAlert)

    private func showPreflightDialog(_ failure: PreflightFailure) {
        let alert = NSAlert()
        switch failure {
        case .screenpipeNotRunning:
            alert.messageText = "screenpipe is not running"
            alert.informativeText = "Open ScreenpipeMenu to start the recorder, then try again."
            alert.addButton(withTitle: "OK")
        case .audioPaused:
            alert.messageText = "Microphone capture is paused"
            alert.informativeText = "ScreenpipeFlow needs the microphone to capture your narration. Resume it in ScreenpipeMenu and try again."
            alert.addButton(withTitle: "OK")
        case .claudeNotFound:
            alert.messageText = "Claude Code CLI not found"
            alert.informativeText = "Install from https://claude.ai/code, then retry. ScreenpipeFlow looked in /usr/local/bin, /opt/homebrew/bin, ~/.claude/local, and ~/.npm-global/bin."
            alert.addButton(withTitle: "OK")
        }
        alert.runModal()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
```

- [ ] **Step 2: Build to verify compilation.**

Run: `swift build`
Expected: no errors.

- [ ] **Step 3: Commit.**

```bash
git add Sources/ScreenpipeFlow/RecordingController.swift
git commit -m "RecordingController: preflight + synth orchestration"
```

---

## Task 13: Menu bar UI

**Files:**
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`

Replace the placeholder menu with the full dropdown: start/stop recording (state-aware label), Grab last 5 min, Open library, Quit. Wires `RecordingController` actions to menu items.

- [ ] **Step 1: Rewrite `ScreenpipeFlowApp.swift`.**

```swift
import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedState: AppState?
    @MainActor static weak var sharedController: RecordingController?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            // Best-effort: if there's an in-flight recording, drop a recovery
            // marker so the next launch can offer to resume. (Implemented in Task 18.)
            Logger.log("app terminating")
        }
    }
}

@main
struct ScreenpipeFlowApp: App {
    @State private var appState = AppState()
    @State private var hotkeys = HotkeyManager()
    @State private var controller: RecordingController? = nil

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Logger.bootstrap()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: appState, controller: controller)
        } label: {
            HStack(spacing: 4) {
                Text(StatusBarLabel.text(for: appState.sessionState))
                Image(systemName: StatusBarLabel.iconName(for: appState.sessionState))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(StatusBarLabel.color(for: appState.sessionState))
            }
            .foregroundStyle(StatusBarLabel.color(for: appState.sessionState))
        }
        .menuBarExtraStyle(.menu)
        .onAppear {
            let c = RecordingController(state: appState)
            controller = c
            AppDelegate.sharedState = appState
            AppDelegate.sharedController = c
            hotkeys.register(HotkeyManager.recordToggle) {
                Task { @MainActor in await toggleRecording(c) }
            }
            hotkeys.register(HotkeyManager.grabLast) {
                Task { @MainActor in appState.beginBrowsingTimeline() }
            }
        }
    }
}

@MainActor
private func toggleRecording(_ controller: RecordingController) async {
    switch AppDelegate.sharedState?.sessionState {
    case .recording: await controller.stop()
    case .idle: await controller.startProactive()
    default: break
    }
}

enum StatusBarLabel {
    static func text(for state: AppState.SessionState) -> String {
        switch state {
        case .idle: return "Flow"
        case .browsingTimeline: return "Pick start"
        case .recording: return "● Rec"
        case .synthesizing: return "Synthesizing"
        case .reviewing: return "Review"
        case .error: return "Error"
        }
    }

    static func color(for state: AppState.SessionState) -> Color {
        switch state {
        case .recording: return .red
        case .synthesizing: return .blue
        case .reviewing: return .green
        case .error: return .red
        default: return .secondary
        }
    }

    static func iconName(for state: AppState.SessionState) -> String {
        switch state {
        case .idle, .browsingTimeline: return "waveform.circle"
        case .recording: return "circle.fill"
        case .synthesizing: return "ellipsis.circle"
        case .reviewing: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

struct MenuView: View {
    let state: AppState
    let controller: RecordingController?

    var body: some View {
        Text("ScreenpipeFlow").font(.headline)
        statusLine
        Divider()

        switch state.sessionState {
        case .idle:
            Button("Start recording  ⌃⌥R") {
                Task { await controller?.startProactive() }
            }
            Button("Grab last 5 minutes…  ⌃⌥G") {
                state.beginBrowsingTimeline()
            }

        case .recording:
            Button("Stop recording  ⌃⌥R") {
                Task { await controller?.stop() }
            }

        case .browsingTimeline:
            Button("Cancel timeline picker") {
                state.cancelBrowsingTimeline()
            }

        case .synthesizing:
            Text("Synthesizing skill — keep working, you'll get a notification.")

        case .reviewing(let url):
            Button("Open review window") {
                openReviewWindow(for: url)
            }

        case .error(let msg):
            Text("⚠ \(msg)").foregroundStyle(.red)
            Button("Dismiss") { state.finalize() }
        }

        Divider()
        Button("Open library") { /* opens LibraryWindow (Task 17) */ }
        Button("Open data folder") {
            NSWorkspace.shared.open(
                FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/skills"))
        }
        Button("Open app log") {
            NSWorkspace.shared.open(Logger.appLogURL)
        }
        Divider()
        Button("Quit") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var statusLine: some View {
        switch state.sessionState {
        case .idle: Text("Idle").font(.caption).foregroundStyle(.secondary)
        case .browsingTimeline: Text("Pick a start point in the timeline window").font(.caption).foregroundStyle(.secondary)
        case .recording: Text("Recording…").font(.caption).foregroundStyle(.red)
        case .synthesizing: Text("Synthesizing…").font(.caption).foregroundStyle(.blue)
        case .reviewing: Text("Skill ready for review").font(.caption).foregroundStyle(.green)
        case .error(let msg): Text(msg).font(.caption).foregroundStyle(.red)
        }
    }

    private func openReviewWindow(for url: URL) {
        // Implemented in Task 16 (ReviewWindow). For now, just open in Finder.
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: Smoke-test.**

```bash
swift run ScreenpipeFlow &
sleep 2
```

Click the menu bar icon. Verify:
- "Flow" label appears (state .idle).
- Dropdown shows "Start recording", "Grab last 5 minutes…", "Open library", "Open data folder", "Open app log", "Quit".
- Clicking "Start recording" → preflight runs. If screenpipe isn't running, you see the preflight dialog. If it is, the label briefly changes to "● Rec".
- The hotkey `⌃⌥R` toggles recording start/stop (verify by watching the menu label change).
- Click "Quit" to exit.

```bash
pkill -f ScreenpipeFlow
```

- [ ] **Step 3: Commit.**

```bash
git add Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "ScreenpipeFlowApp: full menu UI + hotkey wiring + state-aware label"
```

---

## Task 14: Recording HUD

**Files:**
- Create: `Sources/ScreenpipeFlow/RecordingHUD.swift`
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` (show HUD when state is `.recording`)

A small floating, non-activating panel shown while actively recording. Displays elapsed time, buffer indicator (mode C), narration hint, and Stop button. Built as an NSPanel hosting SwiftUI content.

- [ ] **Step 1: Implement `RecordingHUD`.**

Create `Sources/ScreenpipeFlow/RecordingHUD.swift`:

```swift
import SwiftUI
import AppKit

/// Manages a single floating HUD window during a recording session.
@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?

    func show(session: RecordingSession, onStop: @escaping () -> Void) {
        if panel != nil { return }
        let hostingView = NSHostingView(rootView: RecordingHUDView(session: session, onStop: onStop))
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 80)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
            styleMask: [.nonactivatingPanel, .hudWindow, .titled],
            backing: .buffered,
            defer: false
        )
        panel.title = "ScreenpipeFlow"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.contentView = hostingView
        panel.center()
        // Push the HUD to the top-right of the active screen
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.maxX - 340, y: frame.maxY - 100))
        }
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func hide() {
        panel?.close()
        panel = nil
    }
}

private struct RecordingHUDView: View {
    let session: RecordingSession
    let onStop: () -> Void
    @State private var now: Date = Date()

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(elapsedString)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if let buf = bufferLabel {
                        Text(buf).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button("Stop", action: onStop)
                .keyboardShortcut(.return)
        }
        .padding(12)
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { d in
            now = d
        }
    }

    private var elapsedString: String {
        let s = Int(now.timeIntervalSince(session.activeRecordingStart))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var bufferLabel: String? {
        guard let bs = session.bufferRangeStart else { return nil }
        let s = Int(session.activeRecordingStart.timeIntervalSince(bs))
        return "Buffer: \(s / 60)m \(s % 60)s"
    }

    private var hint: String {
        session.bufferRangeStart == nil
            ? "Narrate what you're doing."
            : "Narrate forward; you can also describe what happened earlier."
    }
}
```

- [ ] **Step 2: Wire the HUD into `ScreenpipeFlowApp`.**

Edit `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`. In the `ScreenpipeFlowApp` struct, add a `@State` for the HUD controller and an `.onChange` that shows/hides it.

Find the body computed property and replace it with:

```swift
    @State private var hud = RecordingHUDController()

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: appState, controller: controller)
        } label: {
            HStack(spacing: 4) {
                Text(StatusBarLabel.text(for: appState.sessionState))
                Image(systemName: StatusBarLabel.iconName(for: appState.sessionState))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(StatusBarLabel.color(for: appState.sessionState))
            }
            .foregroundStyle(StatusBarLabel.color(for: appState.sessionState))
        }
        .menuBarExtraStyle(.menu)
        .onAppear {
            let c = RecordingController(state: appState)
            controller = c
            AppDelegate.sharedState = appState
            AppDelegate.sharedController = c
            hotkeys.register(HotkeyManager.recordToggle) {
                Task { @MainActor in await toggleRecording(c) }
            }
            hotkeys.register(HotkeyManager.grabLast) {
                Task { @MainActor in appState.beginBrowsingTimeline() }
            }
        }
        .onChange(of: appState.sessionState) { _, new in
            switch new {
            case .recording(let session):
                hud.show(session: session) {
                    Task { @MainActor in await controller?.stop() }
                }
            default:
                hud.hide()
            }
        }
    }
```

- [ ] **Step 3: Smoke-test.**

```bash
swift run ScreenpipeFlow &
sleep 2
```

Click "Start recording". Verify a floating HUD appears in the top-right of the screen with a red dot, "0:00" timer, "Narrate what you're doing." hint, and a Stop button. The timer ticks up. Clicking Stop dismisses the HUD and (assuming screenpipe + claude are set up) starts synthesis.

```bash
pkill -f ScreenpipeFlow
```

- [ ] **Step 4: Commit.**

```bash
git add Sources/ScreenpipeFlow/RecordingHUD.swift Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "RecordingHUD: floating NSPanel with elapsed timer + buffer indicator"
```

---

## Task 15: Timeline window (Mode C)

**Files:**
- Create: `Sources/ScreenpipeFlow/TimelineWindow.swift`
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` (open Window scene on `.browsingTimeline`)

Mode C UI: a window with a horizontal strip of thumbnails (queried via `ScreenpipeClient.thumbnailIndex`), a draggable start-point handle, and a "Begin from here" button.

V1 uses *text labels* — app name + timestamp — not pixel thumbnails (per spec section 7 open question: HTTP is simpler, pixel thumbnails deferred). The strip is a vertical list, sorted newest-first, with the user clicking a row to set the start point.

- [ ] **Step 1: Implement `TimelineWindow`.**

Create `Sources/ScreenpipeFlow/TimelineWindow.swift`:

```swift
import SwiftUI

struct TimelineWindow: View {
    let state: AppState
    let controller: RecordingController?

    @State private var items: [ScreenpipeClient.ThumbnailItem] = []
    @State private var lookbackMinutes: Int = 30
    @State private var selected: ScreenpipeClient.ThumbnailItem?
    @State private var loading: Bool = false
    @State private var loadError: String?

    private let client = ScreenpipeClient()
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pick where the task started")
                .font(.headline)

            HStack {
                Text("Look back:")
                Picker("", selection: $lookbackMinutes) {
                    Text("15 min").tag(15)
                    Text("30 min").tag(30)
                    Text("1 hour").tag(60)
                    Text("2 hours").tag(120)
                }
                .frame(width: 120)
                .labelsHidden()
                Button("Reload") { Task { await load() } }
            }

            if loading {
                ProgressView().padding(.vertical, 30).frame(maxWidth: .infinity)
            } else if let err = loadError {
                Text("Failed to load timeline: \(err)").foregroundStyle(.red)
            } else if items.isEmpty {
                Text("No screenpipe data in that range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            } else {
                List(items, id: \.timestamp, selection: $selected) { item in
                    HStack {
                        Text(formatter.string(from: item.timestamp))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        Text(item.appName).bold()
                        Text(item.windowName).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                    }
                    .tag(item)
                    .contentShape(Rectangle())
                }
                .frame(minHeight: 300)
            }

            if let sel = selected {
                let now = Date()
                let secs = Int(now.timeIntervalSince(sel.timestamp))
                Text("Selected window: \(formatter.string(from: sel.timestamp)) → now (\(secs / 60)m \(secs % 60)s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button("Cancel") { state.cancelBrowsingTimeline() }
                Button("Begin from here") {
                    if let sel = selected {
                        Task { await controller?.startRetroactive(bufferStart: sel.timestamp) }
                    }
                }
                .disabled(selected == nil)
                .keyboardShortcut(.return)
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 480)
        .task { await load() }
    }

    private func load() async {
        loading = true
        loadError = nil
        defer { loading = false }
        let now = Date()
        let start = now.addingTimeInterval(-Double(lookbackMinutes) * 60)
        do {
            let raw = try await client.thumbnailIndex(from: start, to: now, limit: 400)
            // Decimate to ~1 entry per ~15 seconds to keep the list manageable.
            items = Self.decimate(raw, minIntervalSec: 15)
                .sorted { $0.timestamp > $1.timestamp }
        } catch {
            loadError = "\(error.localizedDescription)"
        }
    }

    static func decimate(_ items: [ScreenpipeClient.ThumbnailItem],
                         minIntervalSec: TimeInterval) -> [ScreenpipeClient.ThumbnailItem] {
        var last: Date? = nil
        var out: [ScreenpipeClient.ThumbnailItem] = []
        for it in items.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let l = last, it.timestamp.timeIntervalSince(l) < minIntervalSec {
                continue
            }
            out.append(it)
            last = it.timestamp
        }
        return out
    }
}
```

- [ ] **Step 2: Open the Timeline window when state becomes `.browsingTimeline`.**

Edit `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`. Add a `Window` scene to the `body`:

```swift
        Window("Timeline", id: "timeline") {
            if case .browsingTimeline = appState.sessionState {
                TimelineWindow(state: appState, controller: controller)
            } else {
                Text("Open me by choosing Grab last N minutes from the menu.")
                    .padding(40)
            }
        }
        .windowResizability(.contentSize)
```

And in the `.onChange` block, when state becomes `.browsingTimeline`, programmatically open the window:

```swift
        .onChange(of: appState.sessionState) { _, new in
            switch new {
            case .recording(let session):
                hud.show(session: session) {
                    Task { @MainActor in await controller?.stop() }
                }
            case .browsingTimeline:
                hud.hide()
                openWindow(id: "timeline")
            default:
                hud.hide()
            }
        }
```

And add `@Environment(\.openWindow) private var openWindow` to the `ScreenpipeFlowApp` struct.

- [ ] **Step 3: Smoke-test.**

```bash
swift run ScreenpipeFlow &
sleep 2
```

(Assumes screenpipe has been running for at least 15 min.) Click menu bar icon → "Grab last 5 minutes…" → Timeline window opens with a list of OCR-event rows. Pick a row. "Selected window: …" appears below. Click "Begin from here" → window closes, HUD appears with the buffer indicator.

```bash
pkill -f ScreenpipeFlow
```

- [ ] **Step 4: Commit.**

```bash
git add Sources/ScreenpipeFlow/TimelineWindow.swift Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "TimelineWindow: mode C start-point picker with lookback selector"
```

---

## Task 16: Review window

**Files:**
- Create: `Sources/ScreenpipeFlow/ReviewWindow.swift`
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` (open Window scene on `.reviewing`)

Shows the synthesized SKILL.md, lets the user edit the name/description, see parameters, and trigger Save / Regenerate / Discard.

V1 keeps it simple: rendered markdown preview (left), parameter list (right), Save/Regenerate/Discard buttons. Step editing is deferred to V2.

- [ ] **Step 1: Implement `ReviewWindow`.**

Create `Sources/ScreenpipeFlow/ReviewWindow.swift`:

```swift
import SwiftUI

struct ReviewWindow: View {
    let state: AppState
    let controller: RecordingController?
    let skillDir: URL

    @State private var skillMarkdown: String = ""
    @State private var loadError: String?
    @State private var feedbackText: String = ""
    @State private var showingRegenerateField: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Left: rendered SKILL.md
            VStack(alignment: .leading, spacing: 4) {
                Text(skillDir.lastPathComponent)
                    .font(.title2)
                Divider()
                if let err = loadError {
                    Text("Failed to load SKILL.md: \(err)").foregroundStyle(.red)
                } else {
                    ScrollView {
                        Text(skillMarkdown)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .border(.tertiary)
                }
            }
            .frame(minWidth: 400)

            // Right: actions
            VStack(alignment: .leading, spacing: 12) {
                Text("Actions").font(.headline)

                Button("Open in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([skillDir])
                }

                Button("Save and close") {
                    state.finalize()
                    closeReviewWindow()
                }
                .keyboardShortcut(.return)

                Divider()

                if showingRegenerateField {
                    Text("Tell the synthesizer what to fix:")
                    TextEditor(text: $feedbackText)
                        .frame(height: 80)
                        .border(.tertiary)
                    Button("Regenerate") {
                        // Need original session — for V1, regenerate from the same
                        // manifest path stored in state. (Track it through state in
                        // a follow-up if this proves limiting.)
                        loadError = "Regenerate requires the original session state — call from the menu while still in the .reviewing state, with the controller holding the prior session reference. See plan task 16 step 1 note."
                    }
                    Button("Cancel") {
                        showingRegenerateField = false
                        feedbackText = ""
                    }
                } else {
                    Button("Regenerate with feedback…") {
                        showingRegenerateField = true
                    }
                }

                Divider()

                Button("Discard skill") {
                    try? FileManager.default.removeItem(at: skillDir)
                    state.removeFlow(slug: skillDir.lastPathComponent)
                    state.finalize()
                    closeReviewWindow()
                }
                .tint(.red)

                Spacer()
            }
            .frame(minWidth: 220)
        }
        .padding(16)
        .frame(minWidth: 720, minHeight: 480)
        .task { loadSkill() }
    }

    private func loadSkill() {
        let md = skillDir.appendingPathComponent("SKILL.md")
        do {
            skillMarkdown = try String(contentsOf: md, encoding: .utf8)
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func closeReviewWindow() {
        // Closing windows in SwiftUI: find the window with id "review" and close it.
        NSApplication.shared.windows.first { $0.title == "Review" }?.close()
    }
}
```

**Note on regenerate:** A clean implementation requires the original `RecordingSession` to be reachable when the user clicks Regenerate. For V1, the simplest path is to keep the most-recent session in `AppState` as `@ObservationIgnored var lastSession: RecordingSession?`, set by `RecordingController.stop()`. Add this in step 2.

- [ ] **Step 2: Add `lastSession` to `AppState` and set it in `RecordingController.stop()`.**

Edit `Sources/ScreenpipeFlow/AppState.swift` — add inside the class:

```swift
    @ObservationIgnored var lastSession: RecordingSession?
    @ObservationIgnored var lastSkillPath: URL?
```

Edit `Sources/ScreenpipeFlow/RecordingController.swift`. In `stop()`, before `runSynthesis`:

```swift
        state.lastSession = session
```

And in `runSynthesis(...)`, after `state.beginReviewing(skill: dir)`:

```swift
                state.lastSkillPath = dir
```

- [ ] **Step 3: Wire Regenerate to use `state.lastSession`.**

Replace the regenerate Button action in `ReviewWindow.swift` with:

```swift
                    Button("Regenerate") {
                        guard let session = state.lastSession,
                              let prevPath = state.lastSkillPath else { return }
                        let feedback = feedbackText
                        Task { @MainActor in
                            await controller?.regenerate(
                                previousSkillPath: prevPath,
                                userFeedback: feedback,
                                originalSession: session)
                        }
                        showingRegenerateField = false
                        feedbackText = ""
                    }
```

- [ ] **Step 4: Add the Review window scene to `ScreenpipeFlowApp`.**

Add to the body of `ScreenpipeFlowApp`:

```swift
        Window("Review", id: "review") {
            if case .reviewing(let url) = appState.sessionState {
                ReviewWindow(state: appState, controller: controller, skillDir: url)
            } else {
                Text("No skill ready for review.").padding(40)
            }
        }
        .windowResizability(.contentSize)
```

And in `.onChange`, on `.reviewing`:

```swift
            case .reviewing:
                hud.hide()
                openWindow(id: "review")
                NSApp.activate(ignoringOtherApps: true)
```

- [ ] **Step 5: Smoke-test.**

Synthesize a real skill (requires screenpipe + claude). When the synthesizer completes, the Review window should open showing the SKILL.md contents. Save & Close, Regenerate, Discard buttons should all behave correctly.

- [ ] **Step 6: Commit.**

```bash
git add Sources/ScreenpipeFlow/ReviewWindow.swift Sources/ScreenpipeFlow/AppState.swift Sources/ScreenpipeFlow/RecordingController.swift Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "ReviewWindow: SKILL.md preview + save/regenerate/discard"
```

---

## Task 17: Library window

**Files:**
- Create: `Sources/ScreenpipeFlow/LibraryWindow.swift`
- Modify: `Sources/ScreenpipeFlow/AppState.swift` (load library from disk on init)
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` (open library Window scene)

Lists all created flows from `~/.claude/skills/`. Each row: name, created date, Open in Finder, Re-open in review, Delete.

- [ ] **Step 1: Add library-loading on AppState init.**

Edit `Sources/ScreenpipeFlow/AppState.swift`. Replace the class with:

```swift
import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case browsingTimeline
        case recording(RecordingSession)
        case synthesizing(URL)
        case reviewing(URL)
        case error(String)
    }

    enum ScreenpipeStatus: Equatable {
        case unknown
        case running
        case audioPaused
        case unhealthy(String)
    }

    private(set) var sessionState: SessionState = .idle
    private(set) var library: [FlowEntry] = []
    private(set) var screenpipeStatus: ScreenpipeStatus = .unknown

    @ObservationIgnored var lastSession: RecordingSession?
    @ObservationIgnored var lastSkillPath: URL?

    init() {
        loadLibraryFromDisk()
    }

    private func loadLibraryFromDisk() {
        let skillsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: skillsDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let entries: [FlowEntry] = contents.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            // Filter to directories that contain SKILL.md AND flow.json — our outputs.
            let skillMD = url.appendingPathComponent("SKILL.md")
            let flowJSON = url.appendingPathComponent("flow.json")
            guard FileManager.default.fileExists(atPath: skillMD.path),
                  FileManager.default.fileExists(atPath: flowJSON.path) else { return nil }
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return FlowEntry(slug: url.lastPathComponent,
                             name: url.lastPathComponent,
                             path: url,
                             createdAt: created)
        }
        library = entries.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Session transitions

    func beginBrowsingTimeline() { sessionState = .browsingTimeline }
    func cancelBrowsingTimeline() { sessionState = .idle }
    func beginRecording(_ session: RecordingSession) { sessionState = .recording(session) }
    func beginSynthesizing(manifest: URL) { sessionState = .synthesizing(manifest) }
    func beginReviewing(skill: URL) { sessionState = .reviewing(skill) }
    func setError(_ message: String) { sessionState = .error(message) }
    func finalize() { sessionState = .idle }

    // MARK: - Library

    func addFlow(_ entry: FlowEntry) {
        library.removeAll { $0.slug == entry.slug }
        library.append(entry)
        library.sort { $0.createdAt > $1.createdAt }
    }

    func removeFlow(slug: String) {
        library.removeAll { $0.slug == slug }
    }

    func reopenFlow(slug: String) {
        guard let entry = library.first(where: { $0.slug == slug }) else { return }
        beginReviewing(skill: entry.path)
    }

    // MARK: - screenpipe status

    func updateScreenpipeStatus(_ status: ScreenpipeStatus) {
        screenpipeStatus = status
    }
}
```

- [ ] **Step 2: Implement `LibraryWindow`.**

Create `Sources/ScreenpipeFlow/LibraryWindow.swift`:

```swift
import SwiftUI

struct LibraryWindow: View {
    let state: AppState

    private let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your flows").font(.title2)
            Divider()

            if state.library.isEmpty {
                VStack(spacing: 8) {
                    Text("No flows yet.").font(.headline)
                    Text("Record a demonstration to create your first one.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                List(state.library) { entry in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(entry.name).bold()
                            Text(dateFmt.string(from: entry.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Open") {
                            NSWorkspace.shared.activateFileViewerSelecting([entry.path])
                        }
                        Button("Review") {
                            state.reopenFlow(slug: entry.slug)
                        }
                        Button("Delete") {
                            try? FileManager.default.removeItem(at: entry.path)
                            state.removeFlow(slug: entry.slug)
                        }
                        .tint(.red)
                    }
                }
            }
        }
        .padding(16)
        .frame(minWidth: 600, minHeight: 400)
    }
}
```

- [ ] **Step 3: Add the Library window scene and the "Open library" menu action.**

Edit `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`. Add to `body`:

```swift
        Window("Library", id: "library") {
            LibraryWindow(state: appState)
        }
        .windowResizability(.contentSize)
```

In `MenuView`, replace the placeholder Open library button:

```swift
        Button("Open library") {
            // open the library window via an environment-injected hook
            NotificationCenter.default.post(name: .openLibrary, object: nil)
        }
```

And add to the top of the file:

```swift
extension Notification.Name {
    static let openLibrary = Notification.Name("openLibrary")
}
```

Then in `ScreenpipeFlowApp.onAppear`:

```swift
            NotificationCenter.default.addObserver(forName: .openLibrary, object: nil, queue: .main) { _ in
                Task { @MainActor in
                    openWindow(id: "library")
                }
            }
```

- [ ] **Step 4: Smoke-test.**

Launch the app. Click "Open library" — empty state appears (if you haven't synthesized anything yet). Manually create a fake skill at `~/.claude/skills/test-flow/` containing a `SKILL.md` and `flow.json` (touch the files), then reopen the library — the entry should appear.

```bash
mkdir -p ~/.claude/skills/test-flow
echo "---\nname: test-flow\n---\n# Test" > ~/.claude/skills/test-flow/SKILL.md
echo "{}" > ~/.claude/skills/test-flow/flow.json
```

Then run the app and verify "test-flow" shows up.

```bash
rm -rf ~/.claude/skills/test-flow
```

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/LibraryWindow.swift Sources/ScreenpipeFlow/AppState.swift Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "LibraryWindow: list created flows; load from disk on init"
```

---

## Task 18: Crash recovery + applicationWillTerminate

**Files:**
- Modify: `Sources/ScreenpipeFlow/AppState.swift` (recovery dir support)
- Modify: `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift` (wire applicationWillTerminate)

If the app is mid-recording when terminated, dump a recovery marker to a known directory. On next launch, surface a prompt to optionally start a mode C recording from the recovery point.

**Note:** Per the spec, mode C is the recovery path — we don't need a special "resume" UX. We just write a marker that says "you were recording from time T; if you want, open mode C and pick a start near T."

- [ ] **Step 1: Add recovery dump + restore logic to `AppState`.**

Edit `Sources/ScreenpipeFlow/AppState.swift` — add inside the class:

```swift
    private var recoveryDir: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScreenpipeFlow/recovery", isDirectory: true)
    }

    /// Called from applicationWillTerminate. If we're mid-recording, leave a marker.
    func writeRecoveryIfNeeded() {
        guard case .recording(let session) = sessionState else { return }
        try? FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let marker: [String: Any] = [
            "mode": session.mode.rawValue,
            "bufferRangeStart": session.bufferRangeStart.map { iso.string(from: $0) } as Any,
            "activeRecordingStart": iso.string(from: session.activeRecordingStart),
            "interruptedAt": iso.string(from: Date())
        ]
        let url = recoveryDir.appendingPathComponent("interrupted-\(UUID().uuidString).json")
        if let data = try? JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted]) {
            try? data.write(to: url, options: .atomic)
            Logger.log("recovery marker written to \(url.path)")
        }
    }

    /// Returns the most recent interrupted-session start time, or nil.
    func loadMostRecentInterruptedStart() -> Date? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: recoveryDir,
            includingPropertiesForKeys: [.creationDateKey]
        ).sorted(by: {
            let a = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let b = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return a > b
        }), let first = entries.first else { return nil }
        guard let data = try? Data(contentsOf: first),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startStr = json["activeRecordingStart"] as? String else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: startStr)
    }

    func clearRecoveryMarkers() {
        try? FileManager.default.removeItem(at: recoveryDir)
    }
```

- [ ] **Step 2: Wire `applicationWillTerminate`.**

In `Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift`, update `AppDelegate`:

```swift
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedState: AppState?
    @MainActor static weak var sharedController: RecordingController?

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.sharedState?.writeRecoveryIfNeeded()
            Logger.log("app terminating")
        }
    }
}
```

- [ ] **Step 3: Show a recovery prompt on launch if a marker exists.**

In `ScreenpipeFlowApp.onAppear`, after the controller is created and hotkeys registered, add:

```swift
            if let interruptedAt = appState.loadMostRecentInterruptedStart() {
                let alert = NSAlert()
                alert.messageText = "An earlier recording was interrupted"
                let fmt = DateFormatter()
                fmt.dateStyle = .none
                fmt.timeStyle = .medium
                alert.informativeText = """
                ScreenpipeFlow detected that a recording started at \
                \(fmt.string(from: interruptedAt)) was interrupted. \
                Use Grab last N minutes from the menu and scroll back to \
                that time to recover the demonstration.
                """
                alert.addButton(withTitle: "OK")
                alert.runModal()
                appState.clearRecoveryMarkers()
            }
```

- [ ] **Step 4: Smoke-test.**

```bash
swift run ScreenpipeFlow &
sleep 2
```

Click Start recording. Wait 5 seconds, then force-kill: `pkill -9 -f ScreenpipeFlow`. Wait, then re-run `swift run ScreenpipeFlow`. The recovery prompt should appear naming approximately when you hit Start.

- [ ] **Step 5: Commit.**

```bash
git add Sources/ScreenpipeFlow/AppState.swift Sources/ScreenpipeFlow/ScreenpipeFlowApp.swift
git commit -m "Crash recovery: marker on terminate + prompt on next launch"
```

---

## Task 19: build-flow.sh — .app bundle assembly

**Files:**
- Create: `build-flow.sh`

Builds `ScreenpipeFlow.app` similarly to the existing `build.sh` for Tool 1: universal binary, manual bundle assembly, ad-hoc codesign. Outputs `ScreenpipeFlow.zip` for distribution.

- [ ] **Step 1: Create `build-flow.sh`.**

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ScreenpipeFlow"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"

cd "$PROJECT_DIR"

echo "==> Building $APP_NAME (universal)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/ScreenpipeFlowInfo.plist "$APP_BUNDLE/Contents/Info.plist"

# The bundled resource file is generated by SwiftPM under
# .build/apple/Products/Release/ScreenpipeFlow_ScreenpipeFlow.bundle/
# Copy it into the .app's Resources/ so Bundle.module can find it at runtime.
SPM_BUNDLE="$PROJECT_DIR/.build/apple/Products/Release/ScreenpipeFlow_ScreenpipeFlow.bundle"
if [ -d "$SPM_BUNDLE" ]; then
    cp -R "$SPM_BUNDLE" "$APP_BUNDLE/Contents/Resources/"
fi

# Sign with the same self-signed cert ScreenpipeMenu uses (if available),
# else fall back to ad-hoc.
CERT_NAME="ScreenpipeMenu Local Dev"
CERT_LINE=$(security find-identity -p basic login.keychain 2>/dev/null | grep "$CERT_NAME" || true)
CERT_SHA=$(echo "$CERT_LINE" | awk '{print $2}' | head -1)

if [ -n "$CERT_SHA" ]; then
    SIGN_IDENTITY="$CERT_SHA"
    echo "==> Codesigning with '$CERT_NAME' ($CERT_SHA)"
else
    SIGN_IDENTITY="-"
    echo "==> Codesigning ad-hoc"
fi

codesign --sign "$SIGN_IDENTITY" --force --identifier com.mengo.screenpipeflow "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
```

- [ ] **Step 2: Make it executable and run it.**

```bash
chmod +x build-flow.sh
./build-flow.sh
```

Expected: a `ScreenpipeFlow.app` is created in the repo root. Launch it from Finder; verify the menu bar icon appears and the dropdown works.

- [ ] **Step 3: Add `ScreenpipeFlow.app` and `ScreenpipeFlow.zip` to `.gitignore`.**

Read the existing `.gitignore`:

```bash
cat .gitignore
```

Add these lines if not present:

```
ScreenpipeFlow.app/
ScreenpipeFlow.zip
```

- [ ] **Step 4: Commit.**

```bash
git add build-flow.sh .gitignore
git commit -m "build-flow.sh: .app bundle assembly + ad-hoc codesign, parallels build.sh"
```

---

## Task 20: install.sh — add ScreenpipeFlow install path

**Files:**
- Modify: `install.sh`

Coworker install flow now installs both apps from the GitHub release. Extend `install.sh` to also download/install ScreenpipeFlow.app.

- [ ] **Step 1: Read the current install.sh.**

```bash
cat install.sh
```

- [ ] **Step 2: Extend it to also install ScreenpipeFlow.**

For V1, the simplest version is to assume the GitHub release contains both `ScreenpipeMenu.zip` and `ScreenpipeFlow.zip`. The script downloads and installs both.

Find the section in `install.sh` that downloads ScreenpipeMenu.zip from the release. Duplicate that block for ScreenpipeFlow.zip, installing it to `~/Applications/ScreenpipeFlow.app`. Both apps install side by side.

Add a final message:

```bash
echo
echo "==> Installed:"
echo "    ~/Applications/ScreenpipeMenu.app   (always-on recorder)"
echo "    ~/Applications/ScreenpipeFlow.app   (demonstration-to-skill recorder)"
echo
echo "Launch ScreenpipeMenu first. Once it shows 'Recording' in green,"
echo "launch ScreenpipeFlow. ScreenpipeFlow needs ScreenpipeMenu running."
```

(Concrete diff depends on the existing install.sh structure — read it first, then mirror the existing download/extract/chmod/launch pattern for the new app.)

- [ ] **Step 3: Smoke-test the install script (locally).**

```bash
./install.sh
```

(In real usage this downloads from the release; for local testing, point the URL at the freshly-built local artifacts via an env var, or skip and rely on the manual smoke test in Task 22.)

- [ ] **Step 4: Commit.**

```bash
git add install.sh
git commit -m "install.sh: also install ScreenpipeFlow.app alongside ScreenpipeMenu"
```

---

## Task 21: Eval harness scaffold

**Files:**
- Create: `evals/screenpipeflow/run-evals.sh`
- Create: `evals/screenpipeflow/README.md`
- Create: `evals/screenpipeflow/fixtures/.gitkeep`

Synthesis regression eval. Not part of the shipping app — a developer tool for catching regressions when iterating on `synthesis-prompt.md`.

- [ ] **Step 1: Create the harness.**

Create `evals/screenpipeflow/run-evals.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Run synthesis evals against each fixture in evals/screenpipeflow/fixtures/.
# Each fixture is a directory containing:
#   - manifest.json        (the synthesizer input)
#   - screenpipe-data/     (exported screenpipe data — frames, transcript, accessibility)
#   - expected.md          (properties the synthesis output must satisfy)
# After running synthesis for each fixture, this script asks claude (as a judge)
# whether the actual output meets the expected criteria and prints a score.

EVAL_DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURE_DIR="$EVAL_DIR/fixtures"

if [ ! -d "$FIXTURE_DIR" ] || [ -z "$(ls -A "$FIXTURE_DIR" 2>/dev/null)" ]; then
    echo "No fixtures in $FIXTURE_DIR — add some via the README."
    exit 0
fi

PROMPT_FILE="$EVAL_DIR/../../Resources/synthesis-prompt.md"
if [ ! -f "$PROMPT_FILE" ]; then
    echo "Missing $PROMPT_FILE"
    exit 1
fi

PROMPT_BODY=$(cat "$PROMPT_FILE")

TOTAL=0
PASSED=0

for fixture in "$FIXTURE_DIR"/*/; do
    name=$(basename "$fixture")
    TOTAL=$((TOTAL + 1))
    echo "==> Fixture: $name"
    manifest="$fixture/manifest.json"
    expected="$fixture/expected.md"
    if [ ! -f "$manifest" ] || [ ! -f "$expected" ]; then
        echo "    SKIP: missing manifest.json or expected.md"
        continue
    fi

    OUT_DIR=$(mktemp -d)
    PROMPT_FOR_FIXTURE="${PROMPT_BODY//\$MANIFEST_PATH/$manifest}"

    # NOTE: for a real eval, you'd need to point claude at the fixture's
    # screenpipe-data instead of the live screenpipe MCP. The simplest way is to
    # run a tiny stub MCP server that serves the fixture data. For V1 of the
    # eval harness, this script is a placeholder — you run it manually with a
    # real screenpipe instance loaded with fixture data.
    echo "    Running claude -p..."
    claude -p "$PROMPT_FOR_FIXTURE" > "$OUT_DIR/out.txt" 2>&1 || true

    JUDGE_PROMPT="Below are the expected criteria for a synthesis output, then the actual synthesis log. Reply with PASS or FAIL on the first line, followed by a brief explanation.

EXPECTED:
$(cat "$expected")

ACTUAL LOG:
$(cat "$OUT_DIR/out.txt")
"
    VERDICT=$(claude -p "$JUDGE_PROMPT" | head -1)
    echo "    Judge: $VERDICT"
    if [[ "$VERDICT" == PASS* ]]; then
        PASSED=$((PASSED + 1))
    fi
    rm -rf "$OUT_DIR"
done

echo
echo "==> $PASSED / $TOTAL passed"
```

- [ ] **Step 2: Create the README.**

Create `evals/screenpipeflow/README.md`:

```markdown
# ScreenpipeFlow synthesis evals

Regression eval for the bootstrap synthesis prompt at `Resources/synthesis-prompt.md`.

Run: `./run-evals.sh`

## Adding a fixture

1. Record a short demonstration via ScreenpipeFlow normally; let it synthesize.
2. Save the manifest (from `~/Library/Application Support/ScreenpipeFlow/manifests/`) as `fixtures/<name>/manifest.json`.
3. Export screenpipe data for the manifest's time range via the screenpipe HTTP API and save as `fixtures/<name>/screenpipe-data/` (or document the time range so it can be re-fetched).
4. Write `fixtures/<name>/expected.md` listing the properties the synthesis output must have:

```
- SKILL.md MUST mention "slack channel" as a parameter
- flow.json MUST contain a step of type=browser with intent containing "dashboard"
- The "Open dashboard" step MUST be tagged inferred: true
```

5. Run `./run-evals.sh` to confirm it passes today. Commit the fixture.

## Iterating on the prompt

When changing `Resources/synthesis-prompt.md`:
1. Run evals before the change. Note the pass count.
2. Make your change.
3. Run evals again. Pass count must not drop.

## Limitations

The runner currently expects a live screenpipe instance with fixture data loaded; injecting fixture data into the screenpipe MCP is a TODO. For now, run manually with screenpipe set up to point at the fixture's data dir.
```

- [ ] **Step 3: Add an empty `.gitkeep`, make the script executable.**

```bash
mkdir -p evals/screenpipeflow/fixtures
touch evals/screenpipeflow/fixtures/.gitkeep
chmod +x evals/screenpipeflow/run-evals.sh
```

- [ ] **Step 4: Commit.**

```bash
git add evals/
git commit -m "evals: scaffold for synthesis regression eval harness"
```

---

## Task 22: Manual smoke test checklist

**Files:**
- Create: `docs/manual-smoke-tests/screenpipeflow-v1.md`

The pre-release checklist. Run this before tagging a V1 release.

- [ ] **Step 1: Create the checklist doc.**

Create `docs/manual-smoke-tests/screenpipeflow-v1.md`:

```markdown
# ScreenpipeFlow V1 — Manual smoke test checklist

Run through this before any release tagged as V1.x. Each item should be a
pass before shipping.

## Preconditions
- macOS 15+, Apple Silicon
- ScreenpipeMenu.app installed and running ("Recording" status in green)
- Claude Code CLI installed (`which claude` returns a path)
- screenpipe MCP configured for Claude Code (`claude mcp list` shows screenpipe)

## A. App lifecycle
- [ ] Launch `~/Applications/ScreenpipeFlow.app` from Finder — menu bar icon appears.
- [ ] Click the icon — dropdown shows the expected items (Start recording, Grab last N min…, Open library, etc).
- [ ] Quit via the menu — process terminates cleanly (`pgrep -f ScreenpipeFlow` returns nothing).

## B. Mode A — Proactive
- [ ] Click Start recording. HUD appears top-right with red dot, timer at 0:00, hint text.
- [ ] Spend 30 seconds doing something narratable (open a webpage, copy a value, paste somewhere) and narrating it out loud.
- [ ] Click Stop. HUD disappears. Menu bar label changes to "Synthesizing".
- [ ] Within 2 minutes, a macOS notification appears: "Skill <name> ready for review."
- [ ] Click the notification — Review window opens showing SKILL.md content with the expected intent + parameters.
- [ ] Click Save and close. The Library window (if open) refreshes; the skill appears in `~/.claude/skills/<slug>/`.
- [ ] Open the skill directory in Finder — contains SKILL.md, flow.json, frames/*.png.
- [ ] Invoke the skill from a new Claude Code session: `claude` → "run <slug>". Claude actually executes the demonstrated task end-to-end.

## C. Mode C — Retroactive
- [ ] Have been doing something narratable for the last 10 minutes (recorded by screenpipe).
- [ ] Click "Grab last 5 minutes…" — Timeline window opens, lists OCR events with timestamps and app names.
- [ ] Scroll the list. Verify it covers approximately the last 30 minutes.
- [ ] Pick a row near where the task started. "Selected window: …" updates.
- [ ] Click "Begin from here." Window closes. HUD appears with the "(Buffer: Xm)" indicator.
- [ ] Narrate briefly: "Earlier I was doing X. Now I'm going to finish by doing Y."
- [ ] Click Stop. Review window appears.
- [ ] Inspect SKILL.md — verify the early steps are tagged as inferred ("inferred from observation — verify").

## D. Variable callouts
- [ ] Start a recording.
- [ ] Mid-recording, narrate: "I'm typing in my email myemail@example.com — that should be a variable, call it user_email."
- [ ] Stop. Review window opens.
- [ ] Verify the Parameters list includes `user_email`.
- [ ] Open SKILL.md — verify literal email is replaced with `{{user_email}}`.

## E. Regenerate-with-feedback
- [ ] Synthesize any skill that comes out slightly wrong.
- [ ] Click Regenerate with feedback. Type a correction. Submit.
- [ ] Verify a new synthesis runs and the skill directory is updated with corrected content.

## F. Error paths
- [ ] Quit ScreenpipeMenu (Tool 1). Then in ScreenpipeFlow, click Start recording. Expected: dialog "screenpipe is not running" with "Open ScreenpipeMenu" hint.
- [ ] Restart ScreenpipeMenu. In its menu, click "Pause audio." In ScreenpipeFlow, click Start recording. Expected: dialog "Microphone capture is paused".
- [ ] Temporarily rename `claude` (e.g. `sudo mv /opt/homebrew/bin/claude /tmp/`). Click Start recording. Expected: dialog "Claude Code CLI not found."
- [ ] Restore `claude`. Click Start recording, then immediately Stop (under 10 sec). Expected: "Recording too short" notification.

## G. Crash recovery
- [ ] Click Start recording.
- [ ] After 5 seconds, force-kill: `pkill -9 -f ScreenpipeFlow`.
- [ ] Relaunch the app. Expected: dialog "An earlier recording was interrupted at HH:MM:SS. Use Grab last N minutes from the menu and scroll back to that time to recover."
- [ ] Verify the marker directory at `~/Library/Application Support/ScreenpipeFlow/recovery/` is empty after the dialog closes.

## H. Library
- [ ] Open the library window. Verify all created skills appear with correct names and dates.
- [ ] Click Open for a skill — Finder opens its directory.
- [ ] Click Review for a skill — Review window opens with its SKILL.md.
- [ ] Click Delete for a skill — disappears from library; directory removed from `~/.claude/skills/`.

## I. Performance / unattended runs
- [ ] Leave the app running idle for an hour. CPU + memory usage stay reasonable (Activity Monitor: < 1% CPU, < 100 MB RSS).
- [ ] Quit and re-launch — library still populated from disk; no stale state.
```

- [ ] **Step 2: Commit.**

```bash
git add docs/manual-smoke-tests/screenpipeflow-v1.md
git commit -m "manual smoke test checklist for ScreenpipeFlow V1"
```

---

## Self-review

Before claiming this plan is complete, run through the spec at [`docs/superpowers/specs/2026-05-12-screenpipeflow-design.md`](../specs/2026-05-12-screenpipeflow-design.md) and verify each requirement maps to a task:

| Spec requirement | Implemented in |
|---|---|
| Proactive mode (A) | Task 12 (`startProactive`), Task 13 (menu), Task 14 (HUD) |
| Retroactive mode (C) | Task 15 (Timeline window), Task 12 (`startRetroactive`) |
| Narration-driven param detection | Task 9 (prompt — synthesizer does it) |
| Auto-detected params with confirm/reject | Task 9 (prompt), Task 16 (Review UI) |
| Manifest schema | Task 5 |
| `SKILL.md` + `flow.json` + `frames/` output | Task 9 (prompt directs claude to produce these) |
| Review window with rename / params / regenerate | Task 16 |
| Library window | Task 17 |
| `claude -p` synthesis (no API tokens) | Task 8, Task 12 |
| screenpipe HTTP client | Tasks 6, 7 |
| Hotkeys (⌃⌥R, ⌃⌥G) | Task 10, Task 13 |
| Preflight: screenpipe / audio / claude / MCP | Task 12 (note: MCP probe is deferred; falls through to claude itself reporting the issue) |
| Crash recovery via marker + mode C | Task 18 |
| applicationWillTerminate handler | Task 18 |
| Unit tests for Swift bookkeeping | Tasks 3, 4, 5, 6, 7, 8, 11 |
| Eval harness scaffold | Task 21 |
| Manual smoke test checklist | Task 22 |
| `.app` bundling + ad-hoc sign | Task 19 |
| install.sh updates | Task 20 |

**Gaps noted (acceptable for V1, follow up if needed):**
- MCP preflight probe is not wired (Task 12 mentions it but doesn't implement). Acceptable because if MCP isn't set up, the synthesizer subprocess fails fast and surfaces a clear error to the user via the "View log" path.
- Pixel thumbnails in Timeline window are deferred — V1 shows text rows instead.
- Settings UI (custom hotkeys, save-path override) is deferred — defaults are used.
