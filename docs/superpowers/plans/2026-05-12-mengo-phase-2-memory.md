# Mengo Desktop — Phase 2 "Mengo Memory" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the screenpipe recorder into Mengo Desktop's lifecycle — starts on launch, stops on quit; pause/resume audio & screen and "Open data folder" work from the menu bar; the Memory pane shows recording status, controls, the screenpipe version, the health readout, and a crash-recovery button.

**Architecture:** A new `RecorderController` (`@Observable @MainActor`) owns the recorder lifecycle, status, and pause/resume. It depends on ported-from-V1 `RecorderProcess` (spawns `screenpipe record`), `APIClient` (HTTP to `127.0.0.1:3030`), and `BinaryManager` (the bundled helper path) — all behind small protocols so the controller is unit-testable with stubs. `MengoDesktopApp` owns the controller as `@State`; the `AppDelegate` calls `start()`/`stop()` from `applicationDidFinishLaunching`/`willTerminate` via a static weak ref (V1's bridge). `build-mengo.sh` gains a build-time screenpipe download → `Contents/Helpers/`, signed with the `ai.mengo.desktop` identifier so the helper inherits the app's TCC grants.

**Tech Stack:** Swift 6 / SwiftUI / AppKit / ScreenCaptureKit / AVFoundation, SwiftPM, XCTest, `sips`/`iconutil`/`codesign`/`ditto`/`curl`/`tar` for packaging.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-phase-2-memory-design.md`](../specs/2026-05-12-mengo-phase-2-memory-design.md)

**Working directory for every command below:** the repo root of the `mengo/phase-2-memory` worktree — `/Users/kylebell/screenpipe/.claude/worktrees/mengo-phase-1-shell` (the directory containing `Package.swift`; it holds the `mengo/phase-2-memory` branch).

---

## File Structure

New under `Sources/MengoDesktop/`:

| File | Responsibility |
|---|---|
| `RecorderStatus.swift` | `enum RecorderStatus: Equatable` (idle/starting/recording/audioPaused/screenPaused/bothPaused/error) + `isRecording` + `static func from(audioPaused:screenPaused:) -> RecorderStatus`. Pure, no AppKit. |
| `RecorderProcess.swift` | `final class RecorderProcess: RecorderProcessControlling` — spawns `<binary> record` with `SCREENPIPE_API_KEY` + augmented `PATH`; stdout/stderr → `~/Library/Logs/MengoDesktop/recorder.log`; `stop()` = SIGTERM→3 s→SIGKILL; `static newToken()`. Plus `protocol RecorderProcessControlling`. Port of V1's `ScreenpipeMenu/RecorderProcess.swift` (paths renamed). |
| `APIClient.swift` | `actor APIClient: RecorderHealthAPI` — `http://127.0.0.1:3030`, Bearer token, 5 s timeout; `health() -> ScreenpipeHealth`, `audioStart()`, `audioStop()`. Plus `struct ScreenpipeHealth: Decodable, Sendable` and `protocol RecorderHealthAPI: Sendable`. Port of V1's `ScreenpipeMenu/APIClient.swift`. |
| `BinaryManager.swift` | `enum BinaryManager` — `binaryURL` (`Bundle.main…/Contents/Helpers/screenpipe`), `ensureBinary() throws -> URL`, `bundledVersion() -> String?`. Port of V1's `ScreenpipeMenu/BinaryManager.swift`. |
| `RecorderController.swift` | `@Observable @MainActor final class RecorderController` — owns a `RecorderProcessControlling` + `RecorderHealthAPI` + health-poll `Task`; published `status`, `screenpipeVersion`, `lastHealth`; methods `start()`, `stop()`, `pauseAudio/resumeAudio`, `pauseScreen/resumeScreen`, `restartAfterCrash`; `dataFolderURL`, `recorderLogURL`. Injectable deps for tests. Adapted from V1's `ScreenpipeMenu/AppState.swift`. |
| `MemoryPane.swift` | `struct MemoryPane: View` — `init(recorder: RecorderController)`. Status line + version/data-dir + pause-resume buttons + health readout + Open-folder/Open-log + (on error) Restart. The real `.memory` pane. |

Modified under `Sources/MengoDesktop/`:

| File | Change |
|---|---|
| `MengoDesktopApp.swift` | Add `@State private var recorder = RecorderController()`; pass `recorder` into `MainWindowView` and `MenuBarContent`; `MenuBarExtra` `label:` → `MenuBarLabel(status: recorder.status)`; `AppDelegate` gains `static weak var sharedRecorder`, `applicationDidFinishLaunching` → `Task { await AppDelegate.sharedRecorder?.start() }`, `applicationWillTerminate` → `MainActor.assumeIsolated { AppDelegate.sharedRecorder?.stop(); Log.line("app terminating") }`. |
| `MainWindowView.swift` | `init(appState:recorder:)`; detail closure → `if appState.selectedSection == .memory { MemoryPane(recorder: recorder) } else { ComingSoonPane(...) }`. |
| `MenuBarContent.swift` | `init(appState:recorder:)`; wire the "Memory" group (Pause/Resume audio & screen, Open data folder, Open recorder log, Restart-on-error); add `struct MenuBarLabel: View`. Flow group stays disabled. |

Other:

| File | Change |
|---|---|
| `Resources/MengoDesktopInfo.plist` | Add `NSMicrophoneUsageDescription`, `NSScreenCaptureUsageDescription`, `NSCameraUsageDescription`, `NSAppTransportSecurity → NSAllowsLocalNetworking`. |
| `build-mengo.sh` | Add: detect host arch → screenpipe arch; resolve latest screenpipe version (npm registry); cache+download the `@screenpipe/cli-darwin-<arch>` tarball; extract `package/bin/{screenpipe, mlx.metallib}` → `Contents/Helpers/`; `chmod +x`; sign `mlx.metallib` + `screenpipe` with `--identifier ai.mengo.desktop`, then the outer `.app`. |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | New checklist. |

Tests under `Tests/MengoDesktopTests/`: `RecorderStatusTests.swift`, `RecorderProcessTests.swift`, `APIClientTests.swift`, `BinaryManagerTests.swift`, `RecorderControllerTests.swift`.

`Tests/MengoDesktopTests/Fixtures/health-ok.json` — a captured screenpipe `/health` response, for `APIClientTests`.

`AppState.swift`, `SidebarSection.swift`, `Theme.swift`, `Log.swift`, `ComingSoonPane.swift` — unchanged.

---

## Task 1: `RecorderStatus` enum + mapping

**Files:**
- Create: `Sources/MengoDesktop/RecorderStatus.swift`
- Create: `Tests/MengoDesktopTests/RecorderStatusTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MengoDesktopTests/RecorderStatusTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class RecorderStatusTests: XCTestCase {

    func test_from_mapsTheFourPauseCombos() {
        XCTAssertEqual(RecorderStatus.from(audioPaused: false, screenPaused: false), .recording)
        XCTAssertEqual(RecorderStatus.from(audioPaused: true,  screenPaused: false), .audioPaused)
        XCTAssertEqual(RecorderStatus.from(audioPaused: false, screenPaused: true),  .screenPaused)
        XCTAssertEqual(RecorderStatus.from(audioPaused: true,  screenPaused: true),  .bothPaused)
    }

    func test_isRecording_trueForActiveStates_falseOtherwise() {
        XCTAssertTrue(RecorderStatus.recording.isRecording)
        XCTAssertTrue(RecorderStatus.audioPaused.isRecording)
        XCTAssertTrue(RecorderStatus.screenPaused.isRecording)
        XCTAssertTrue(RecorderStatus.bothPaused.isRecording)
        XCTAssertFalse(RecorderStatus.idle.isRecording)
        XCTAssertFalse(RecorderStatus.starting.isRecording)
        XCTAssertFalse(RecorderStatus.error("x").isRecording)
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run: `swift test --filter RecorderStatusTests`
Expected: FAIL — "cannot find 'RecorderStatus' in scope".

- [ ] **Step 3: Create the enum**

Create `Sources/MengoDesktop/RecorderStatus.swift`:

```swift
import Foundation

/// The recorder's user-facing state. Mirrors V1's `ScreenpipeMenu/AppState.Status`
/// (renamed `vision`→`screen` to match the UI wording).
enum RecorderStatus: Equatable {
    case idle
    case starting
    case recording
    case audioPaused
    case screenPaused
    case bothPaused
    case error(String)

    /// True while screenpipe is meant to be running (recording or partially paused).
    var isRecording: Bool {
        switch self {
        case .recording, .audioPaused, .screenPaused, .bothPaused: return true
        case .idle, .starting, .error: return false
        }
    }

    /// Combine the two pause axes into a single status. Only valid while running —
    /// callers in `.idle` / `.starting` / `.error` don't use this.
    static func from(audioPaused: Bool, screenPaused: Bool) -> RecorderStatus {
        switch (audioPaused, screenPaused) {
        case (false, false): return .recording
        case (true,  false): return .audioPaused
        case (false, true):  return .screenPaused
        case (true,  true):  return .bothPaused
        }
    }
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `swift test --filter RecorderStatusTests`
Expected: PASS — 2 tests, 0 failures.

- [ ] **Step 5: Build the app target**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/MengoDesktop/RecorderStatus.swift Tests/MengoDesktopTests/RecorderStatusTests.swift
git commit -m "MengoDesktop: RecorderStatus enum + (audio,screen)->status mapping (TDD)"
```

---

## Task 2: `RecorderProcess` (port from V1) + protocol

**Files:**
- Create: `Sources/MengoDesktop/RecorderProcess.swift`
- Create: `Tests/MengoDesktopTests/RecorderProcessTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MengoDesktopTests/RecorderProcessTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class RecorderProcessTests: XCTestCase {

    func test_newToken_isSpPrefixedEightHex() {
        let token = RecorderProcess.newToken()
        XCTAssertNotNil(token.range(of: #"^sp-[0-9a-f]{8}$"#, options: .regularExpression),
                        "unexpected token: \(token)")
    }

    func test_newToken_isDifferentEachCall() {
        XCTAssertNotEqual(RecorderProcess.newToken(), RecorderProcess.newToken())
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run: `swift test --filter RecorderProcessTests`
Expected: FAIL — "cannot find 'RecorderProcess' in scope".

- [ ] **Step 3: Create `RecorderProcess.swift` (ported, paths renamed)**

Create `Sources/MengoDesktop/RecorderProcess.swift`:

```swift
import Foundation

/// The recorder-process operations `RecorderController` depends on. Lets tests
/// drive the controller with a stub instead of spawning a real screenpipe.
protocol RecorderProcessControlling: AnyObject {
    var isRunning: Bool { get }
    func start(binaryURL: URL) throws
    func stop()
}

/// Spawns and tears down the bundled `screenpipe record` helper. Ported from
/// V1's `ScreenpipeMenu/RecorderProcess.swift`; log path renamed to MengoDesktop.
final class RecorderProcess: RecorderProcessControlling {
    private var process: Process?
    private var logHandle: FileHandle?
    let token: String
    let logFileURL: URL

    init(token: String) {
        self.token = token
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MengoDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("recorder.log")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Spawn `binaryURL record` with our auth token in the env. Truncates the log on each start.
    func start(binaryURL: URL) throws {
        guard !isRunning else { return }

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logFileURL)
        self.logHandle = handle

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["record"]
        var env = ProcessInfo.processInfo.environment
        env["SCREENPIPE_API_KEY"] = token
        // .app processes launched via Finder get a minimal PATH that omits the user's
        // shell paths — and screenpipe needs to find ffmpeg. Prepend common locations.
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(NSHomeDirectory())/bin:\(existingPath)"
        proc.environment = env
        proc.standardOutput = handle
        proc.standardError = handle

        try proc.run()
        self.process = proc
    }

    /// SIGTERM, wait up to 3 s, then SIGKILL.
    func stop() {
        guard let proc = process, proc.isRunning else {
            try? logHandle?.close(); logHandle = nil; process = nil
            return
        }
        proc.terminate()
        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }
        try? logHandle?.close()
        logHandle = nil
        process = nil
    }

    static func newToken() -> String {
        let hex = (0..<8).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined()
        return "sp-\(hex)"
    }
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `swift test --filter RecorderProcessTests`
Expected: PASS — 2 tests, 0 failures.

- [ ] **Step 5: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/MengoDesktop/RecorderProcess.swift Tests/MengoDesktopTests/RecorderProcessTests.swift
git commit -m "MengoDesktop: RecorderProcess (ported from V1) + RecorderProcessControlling protocol"
```

---

## Task 3: `APIClient` (port from V1) + protocol + health type

**Files:**
- Create: `Sources/MengoDesktop/APIClient.swift`
- Create: `Tests/MengoDesktopTests/Fixtures/health-ok.json`
- Create: `Tests/MengoDesktopTests/APIClientTests.swift`

- [ ] **Step 1: Create the fixture**

Create `Tests/MengoDesktopTests/Fixtures/health-ok.json` (a representative screenpipe `/health` body; extra fields are tolerated by the decoder):

```json
{
  "status": "healthy",
  "frame_status": "ok",
  "audio_status": "ok",
  "last_frame_timestamp": "2026-05-12T19:04:58.000Z",
  "message": "all systems nominal"
}
```

- [ ] **Step 2: Write the failing test**

Create `Tests/MengoDesktopTests/APIClientTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class APIClientTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func test_screenpipeHealth_decodesCoreFields_ignoringExtras() throws {
        let data = try loadFixture("health-ok.json")
        let health = try JSONDecoder().decode(ScreenpipeHealth.self, from: data)
        XCTAssertEqual(health.status, "healthy")
        XCTAssertEqual(health.frameStatus, "ok")
        XCTAssertEqual(health.audioStatus, "ok")
    }

    func test_screenpipeHealth_decodesFromMinimalBody() throws {
        let data = Data(#"{"status":"healthy","frame_status":"ok","audio_status":"degraded"}"#.utf8)
        let health = try JSONDecoder().decode(ScreenpipeHealth.self, from: data)
        XCTAssertEqual(health.audioStatus, "degraded")
    }

    func test_apiClient_baseURLIsLocalScreenpipe() async {
        let client = APIClient(token: "sp-deadbeef")
        XCTAssertEqual(await client.baseURLForTesting.absoluteString, "http://127.0.0.1:3030")
    }
}
```

- [ ] **Step 3: Run test — expect compile failure**

Run: `swift test --filter APIClientTests`
Expected: FAIL — "cannot find 'ScreenpipeHealth' / 'APIClient' in scope".

- [ ] **Step 4: Create `APIClient.swift`**

Create `Sources/MengoDesktop/APIClient.swift`:

```swift
import Foundation

/// screenpipe's `/health` response, core fields only. screenpipe may include
/// more — those are ignored. (Renamed/flattened from V1's `APIClient.HealthStatus`.)
struct ScreenpipeHealth: Decodable, Sendable {
    let status: String
    let frameStatus: String
    let audioStatus: String

    private enum CodingKeys: String, CodingKey {
        case status
        case frameStatus = "frame_status"
        case audioStatus = "audio_status"
    }
}

/// The screenpipe HTTP operations `RecorderController` depends on.
protocol RecorderHealthAPI: Sendable {
    func health() async throws -> ScreenpipeHealth
    func audioStart() async throws
    func audioStop() async throws
}

/// Thin client over screenpipe's local HTTP API. Ported from V1's
/// `ScreenpipeMenu/APIClient.swift`.
actor APIClient: RecorderHealthAPI {
    private let baseURL = URL(string: "http://127.0.0.1:3030")!
    private let token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    /// Exposed for tests.
    var baseURLForTesting: URL { baseURL }

    enum APIError: Error {
        case badStatus(Int)
        case noResponse
    }

    func health() async throws -> ScreenpipeHealth {
        try await get("/health", as: ScreenpipeHealth.self)
    }

    func audioStop() async throws { try await post("/audio/stop") }
    func audioStart() async throws { try await post("/audio/start") }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: req)
        try check(response)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }
}
```

> Note on the test target & resources: the fixture is read via `#filePath`-relative path, not a SwiftPM resource bundle — so no `resources:` clause is needed on `MengoDesktopTests` in `Package.swift`. (If `swift test` ever can't find `Fixtures/`, add `resources: [.copy("Fixtures")]` to the test target and load via `Bundle.module` instead.)

- [ ] **Step 5: Run test — expect PASS**

Run: `swift test --filter APIClientTests`
Expected: PASS — 3 tests, 0 failures.

- [ ] **Step 6: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 7: Commit**

```bash
git add Sources/MengoDesktop/APIClient.swift Tests/MengoDesktopTests/APIClientTests.swift Tests/MengoDesktopTests/Fixtures/health-ok.json
git commit -m "MengoDesktop: APIClient (ported from V1) + RecorderHealthAPI protocol + ScreenpipeHealth"
```

---

## Task 4: `BinaryManager` (port from V1)

**Files:**
- Create: `Sources/MengoDesktop/BinaryManager.swift`
- Create: `Tests/MengoDesktopTests/BinaryManagerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MengoDesktopTests/BinaryManagerTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class BinaryManagerTests: XCTestCase {

    func test_binaryURL_landsInsideBundledHelpers() {
        XCTAssertTrue(BinaryManager.binaryURL.path.hasSuffix("/Contents/Helpers/screenpipe"),
                      "expected bundled-helper path, got: \(BinaryManager.binaryURL.path)")
    }

    func test_ensureBinary_throwsWhenMissing() {
        // In the test bundle there is no Contents/Helpers/screenpipe, so this must throw.
        XCTAssertThrowsError(try BinaryManager.ensureBinary())
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run: `swift test --filter BinaryManagerTests`
Expected: FAIL — "cannot find 'BinaryManager' in scope".

- [ ] **Step 3: Create `BinaryManager.swift`**

Create `Sources/MengoDesktop/BinaryManager.swift`:

```swift
import Foundation

/// Locates the bundled `screenpipe` helper. Ported from V1's
/// `ScreenpipeMenu/BinaryManager.swift`. The binary is embedded at build time
/// (`build-mengo.sh`) — bundling, rather than downloading at runtime, is what
/// lets the spawned helper inherit Mengo Desktop's Screen Recording / Microphone
/// TCC grants (macOS treats helpers inside a sealed `.app` as part of the parent).
enum BinaryManager {
    enum BinaryError: Swift.Error {
        case binaryNotFound(searched: String)
    }

    static var binaryURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/screenpipe")
    }

    static func ensureBinary() throws -> URL {
        let path = binaryURL.path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw BinaryError.binaryNotFound(searched: path)
        }
        return binaryURL
    }

    /// Read the bundled screenpipe version via `--version`. Blocks briefly — only
    /// called during recorder startup.
    static func bundledVersion() -> String? {
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else { return nil }
        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["--version"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // `screenpipe --version` prints e.g. "screenpipe 0.3.327".
        return text.split(separator: " ").last.map(String.init)
    }
}
```

- [ ] **Step 4: Run test — expect PASS**

Run: `swift test --filter BinaryManagerTests`
Expected: PASS — 2 tests, 0 failures.

- [ ] **Step 5: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!`

- [ ] **Step 6: Commit**

```bash
git add Sources/MengoDesktop/BinaryManager.swift Tests/MengoDesktopTests/BinaryManagerTests.swift
git commit -m "MengoDesktop: BinaryManager (ported from V1) — bundled-helper path + version read"
```

---

## Task 5: `RecorderController` (the Mengo Memory brain)

**Files:**
- Create: `Sources/MengoDesktop/RecorderController.swift`
- Create: `Tests/MengoDesktopTests/RecorderControllerTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/MengoDesktopTests/RecorderControllerTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

private enum StubError: Error { case boom }

@MainActor
final class RecorderControllerTests: XCTestCase {

    // MARK: Stubs

    final class StubProcess: RecorderProcessControlling {
        var running = false
        var shouldFailStart = false
        private(set) var startCount = 0
        private(set) var stopCount = 0
        var isRunning: Bool { running }
        func start(binaryURL: URL) throws {
            if shouldFailStart { throw StubError.boom }
            startCount += 1; running = true
        }
        func stop() { stopCount += 1; running = false }
    }

    actor StubAPI: RecorderHealthAPI {
        var shouldFailHealth = false
        private(set) var audioStopCount = 0
        private(set) var audioStartCount = 0
        func setShouldFailHealth(_ v: Bool) { shouldFailHealth = v }
        func health() async throws -> ScreenpipeHealth {
            if shouldFailHealth { throw URLError(.cannotConnectToHost) }
            return ScreenpipeHealth(status: "healthy", frameStatus: "ok", audioStatus: "ok")
        }
        func audioStop() async throws { audioStopCount += 1 }
        func audioStart() async throws { audioStartCount += 1 }
    }

    // MARK: Helpers

    /// Build a controller wired to stubs — no real screenpipe / TCC / poll delay.
    private func makeController(process: StubProcess = StubProcess(),
                               api: StubAPI = StubAPI(),
                               ensureBinary: @escaping () throws -> URL = { URL(fileURLWithPath: "/tmp/fake-screenpipe") })
        -> RecorderController {
        RecorderController(
            processFactory: { _ in process },
            apiFactory: { _ in api },
            ensureBinary: ensureBinary,
            requestPermissions: { },
            pollInterval: .milliseconds(1)
        )
    }

    private func eventually(timeout: Duration = .seconds(2),
                            file: StaticString = #filePath, line: UInt = #line,
                            _ predicate: @MainActor () -> Bool) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("condition not met within \(timeout)", file: file, line: line)
    }

    // MARK: Tests

    func test_fresh_isIdle() {
        XCTAssertEqual(makeController().status, .idle)
    }

    func test_start_thenHealthyPoll_reachesRecording() async {
        let c = makeController()
        await c.start()
        XCTAssertEqual(c.status, .starting)
        await eventually { c.status == .recording }
    }

    func test_start_whenBinaryMissing_setsError() async {
        let c = makeController(ensureBinary: { throw BinaryManager.BinaryError.binaryNotFound(searched: "/x") })
        await c.start()
        guard case .error = c.status else { return XCTFail("expected .error, got \(c.status)") }
    }

    func test_pauseAudio_thenResume() async {
        let api = StubAPI()
        let c = makeController(api: api)
        await c.start()
        await eventually { c.status == .recording }
        await c.pauseAudio()
        XCTAssertEqual(c.status, .audioPaused)
        let stops = await api.audioStopCount
        XCTAssertEqual(stops, 1)
        await c.resumeAudio()
        XCTAssertEqual(c.status, .recording)
        let starts = await api.audioStartCount
        XCTAssertEqual(starts, 1)
    }

    func test_pauseScreen_stopsProcess_thenResumeRestarts() async {
        let proc = StubProcess()
        let c = makeController(process: proc)
        await c.start()
        await eventually { c.status == .recording }
        let startsBefore = proc.startCount
        await c.pauseScreen()
        XCTAssertEqual(c.status, .screenPaused)
        XCTAssertEqual(proc.stopCount, 1)
        await c.resumeScreen()
        await eventually { c.status == .recording }
        XCTAssertEqual(proc.startCount, startsBefore + 1)
    }

    func test_repeatedHealthFailures_goToError() async {
        let api = StubAPI()
        let c = makeController(api: api)
        await c.start()
        await eventually { c.status == .recording }
        await api.setShouldFailHealth(true)
        await eventually(timeout: .seconds(3)) {
            if case .error = c.status { return true } else { return false }
        }
    }

    func test_restartAfterCrash_fromError_goesToStarting() async {
        let c = makeController()
        await c.start()
        c.forceErrorForTesting("boom")
        guard case .error = c.status else { return XCTFail() }
        await c.restartAfterCrash()
        XCTAssertEqual(c.status, .starting)
    }
}
```

- [ ] **Step 2: Run test — expect compile failure**

Run: `swift test --filter RecorderControllerTests`
Expected: FAIL — "cannot find 'RecorderController' in scope".

- [ ] **Step 3: Create `RecorderController.swift`**

Create `Sources/MengoDesktop/RecorderController.swift`:

```swift
import Foundation
import Observation
import AVFoundation
import ScreenCaptureKit

/// Owns the screenpipe recorder lifecycle for Mengo Memory. Adapted from V1's
/// `ScreenpipeMenu/AppState.swift`, with dependencies injectable for tests.
@Observable
@MainActor
final class RecorderController {

    private(set) var status: RecorderStatus = .idle
    private(set) var screenpipeVersion: String?
    private(set) var lastHealth: ScreenpipeHealth?

    @ObservationIgnored private let process: RecorderProcessControlling
    @ObservationIgnored private let api: RecorderHealthAPI
    @ObservationIgnored private let ensureBinaryClosure: () throws -> URL
    @ObservationIgnored private let requestPermissionsClosure: () async -> Void
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private(set) var healthTask: Task<Void, Never>?
    @ObservationIgnored private var audioPaused = false
    @ObservationIgnored private var screenPaused = false

    init(
        processFactory: (String) -> RecorderProcessControlling = { RecorderProcess(token: $0) },
        apiFactory: (String) -> RecorderHealthAPI = { APIClient(token: $0) },
        ensureBinary: @escaping () throws -> URL = { try BinaryManager.ensureBinary() },
        requestPermissions: @escaping () async -> Void = RecorderController.requestSystemPermissions,
        pollInterval: Duration = .seconds(5)
    ) {
        let token = RecorderProcess.newToken()
        self.process = processFactory(token)
        self.api = apiFactory(token)
        self.ensureBinaryClosure = ensureBinary
        self.requestPermissionsClosure = requestPermissions
        self.pollInterval = pollInterval
        AppDelegate.sharedRecorder = self   // V1's bridge for the AppDelegate hooks
    }

    var dataFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screenpipe")
    }
    var recorderLogURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MengoDesktop/recorder.log")
    }

    // MARK: - Lifecycle

    /// Called from `applicationDidFinishLaunching`. Ensures the bundled helper,
    /// requests TCC, spawns `screenpipe record`, begins health polling.
    func start() async {
        let binaryURL: URL
        do { binaryURL = try ensureBinaryClosure() }
        catch {
            status = .error("screenpipe helper missing — rebuild the app (\(error))")
            return
        }
        screenpipeVersion = BinaryManager.bundledVersion()
        await requestPermissionsClosure()
        await spawnAndPoll(binaryURL: binaryURL)
    }

    private func spawnAndPoll(binaryURL: URL) async {
        do { try process.start(binaryURL: binaryURL) }
        catch {
            status = .error("failed to start recorder: \(error)")
            return
        }
        status = .starting
        startHealthPolling()
    }

    /// Called from `applicationWillTerminate` — synchronous on the main actor so it
    /// finishes before the OS reaps us.
    func stop() {
        healthTask?.cancel()
        healthTask = nil
        process.stop()
        status = .idle
    }

    // MARK: - Pause / resume

    func pauseAudio() async {
        do {
            try await api.audioStop()
            audioPaused = true
            recompute()
        } catch { status = .error("pause audio failed: \(error)") }
    }

    func resumeAudio() async {
        do {
            try await api.audioStart()
            audioPaused = false
            recompute()
        } catch { status = .error("resume audio failed: \(error)") }
    }

    func pauseScreen() async {
        healthTask?.cancel(); healthTask = nil
        process.stop()
        screenPaused = true
        recompute()
    }

    func resumeScreen() async {
        screenPaused = false
        let wasAudioPaused = audioPaused
        do {
            let binaryURL = try ensureBinaryClosure()
            try process.start(binaryURL: binaryURL)
            status = .starting
            startHealthPolling()
            if wasAudioPaused {
                try? await Task.sleep(for: .seconds(8))
                await pauseAudio()
            }
        } catch { status = .error("resume screen failed: \(error)") }
    }

    func restartAfterCrash() async {
        process.stop()
        healthTask?.cancel(); healthTask = nil
        audioPaused = false; screenPaused = false
        do {
            let binaryURL = try ensureBinaryClosure()
            await spawnAndPoll(binaryURL: binaryURL)
        } catch { status = .error("restart failed: \(error)") }
    }

    // MARK: - Health polling

    private func startHealthPolling() {
        healthTask?.cancel()
        let api = self.api
        let interval = self.pollInterval
        healthTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    let health = try await api.health()
                    failures = 0
                    await MainActor.run {
                        guard let self else { return }
                        self.lastHealth = health
                        if case .starting = self.status { self.recompute() }
                    }
                } catch {
                    failures += 1
                    if failures >= 6 {   // ~6 × pollInterval of consecutive failures
                        await MainActor.run { self?.status = .error("recorder not responding") }
                        return
                    }
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func recompute() {
        status = .from(audioPaused: audioPaused, screenPaused: screenPaused)
    }

    /// Test seam — force an `.error` without a real failure.
    func forceErrorForTesting(_ message: String) { status = .error(message) }

    // MARK: - TCC

    /// Trigger the Screen Recording + Microphone prompts so macOS records the grants
    /// against Mengo Desktop; the bundled helper then inherits them. V1's approach.
    /// `nonisolated` so it's a plain `() async -> Void` usable as the closure default.
    nonisolated static func requestSystemPermissions() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch { print("screen-capture permission request failed: \(error)") }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
}
```

> **Concurrency notes (resolve if the Swift 6 checker complains):** `RecorderHealthAPI` already requires `Sendable` (the `APIClient` actor satisfies it; the test `StubAPI` is an actor). `RecorderProcessControlling` is only ever touched from the main actor, so a plain (non-`Sendable`) existential is fine — if a diagnostic appears anyway, mark the test `StubProcess` `@unchecked Sendable` rather than `@MainActor`-isolating `RecorderProcess` (which would block the main actor for 3 s during `stop()`). The `processFactory` / `apiFactory` params are non-`@escaping` (called synchronously in `init`); `ensureBinary` / `requestPermissions` are `@escaping` (stored). If passing `RecorderController.requestSystemPermissions` as the default still trips on isolation, give the `requestPermissions` param a `@Sendable` attribute.

- [ ] **Step 4: Run tests — expect PASS**

Run: `swift test --filter RecorderControllerTests`
Expected: PASS — 8 tests, 0 failures. (If `test_repeatedHealthFailures_goToError` flakes on timing, bump its `eventually` timeout — the poll interval is 1 ms so 6 failures take ~6 ms, but CI scheduling can stretch that.)

- [ ] **Step 5: Build + full suite**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all tests pass (Phase 1's 51 + Phase 2's new ones).

- [ ] **Step 6: Commit**

```bash
git add Sources/MengoDesktop/RecorderController.swift Tests/MengoDesktopTests/RecorderControllerTests.swift
git commit -m "MengoDesktop: RecorderController — recorder lifecycle/status/pause-resume (adapted from V1; injectable for tests)"
```

---

## Task 6: `MemoryPane` view

**Files:**
- Create: `Sources/MengoDesktop/MemoryPane.swift`

(No unit test — SwiftUI view; verified visually in the smoke checklist.)

- [ ] **Step 1: Create `MemoryPane.swift`**

Create `Sources/MengoDesktop/MemoryPane.swift`:

```swift
import SwiftUI

/// The Memory product's pane in the main window. Reads the `RecorderController`.
struct MemoryPane: View {
    let recorder: RecorderController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusHeader

            HStack(spacing: 24) {
                audioControl
                screenControl
            }

            if case .error(let message) = recorder.status {
                Button("Restart recorder") { Task { await recorder.restartAfterCrash() } }
                Text(message).font(Theme.caption).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Recorder").font(Theme.headline)
                row("Data folder", recorder.dataFolderURL.path)
                row("Screen capture", recorder.lastHealth?.frameStatus ?? "—")
                row("Audio capture", recorder.lastHealth?.audioStatus ?? "—")
            }

            HStack {
                Button("Open data folder") { NSWorkspace.shared.open(recorder.dataFolderURL) }
                Button("Open recorder log") { NSWorkspace.shared.open(recorder.recorderLogURL) }
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paneBackground)
    }

    @ViewBuilder private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph).foregroundStyle(color)
            Text(headline).font(Theme.title).foregroundStyle(color == .secondary ? Theme.primaryText : color)
        }
        if let v = recorder.screenpipeVersion {
            Text("screenpipe v\(v)").font(Theme.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var audioControl: some View {
        switch recorder.status {
        case .audioPaused, .bothPaused:
            Button("Resume audio") { Task { await recorder.resumeAudio() } }
        default:
            Button("Pause audio") { Task { await recorder.pauseAudio() } }
                .disabled(!recorder.status.isRecording)
        }
    }

    @ViewBuilder private var screenControl: some View {
        switch recorder.status {
        case .screenPaused, .bothPaused:
            Button("Resume screen") { Task { await recorder.resumeScreen() } }
        default:
            Button("Pause screen") { Task { await recorder.pauseScreen() } }
                .disabled(!recorder.status.isRecording)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(Theme.primaryText)
        }
        .font(Theme.body)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var headline: String {
        switch recorder.status {
        case .idle:        return "Idle"
        case .starting:    return "Starting…"
        case .recording:   return "● Recording"
        case .audioPaused: return "● Audio paused (screen recording)"
        case .screenPaused:return "● Screen paused (audio recording)"
        case .bothPaused:  return "● Paused"
        case .error(let m):return "⚠ \(m)"
        }
    }
    private var glyph: String {
        switch recorder.status {
        case .recording: return "circle.fill"
        case .audioPaused, .screenPaused, .bothPaused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .starting, .idle: return "circle.dotted"
        }
    }
    private var color: Color {
        switch recorder.status {
        case .recording: return .green
        case .audioPaused, .screenPaused, .bothPaused: return .yellow
        case .error: return .red
        case .starting, .idle: return .secondary
        }
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build --product MengoDesktop`
Expected: `Build complete!` (the file compiles even though nothing references it yet).

- [ ] **Step 3: Commit**

```bash
git add Sources/MengoDesktop/MemoryPane.swift
git commit -m "MengoDesktop: MemoryPane — recorder status, controls, health readout, crash-recovery"
```

---

## Task 7: Thread `RecorderController` through the app + wire lifecycle

**Files:**
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift`
- Modify: `Sources/MengoDesktop/MainWindowView.swift`

(`MenuBarContent` is left exactly as Phase 1 in this task — the recorder reaches it in Task 8, when its Memory group goes live. Keeping it untouched here keeps the build green.)

- [ ] **Step 1: Update `MainWindowView.swift`**

Replace `Sources/MengoDesktop/MainWindowView.swift` with:

```swift
import SwiftUI

/// The main window: a `NavigationSplitView` with a five-row sidebar; the detail
/// column shows the section's pane (real `MemoryPane` for `.memory`, placeholders
/// for the rest in Phase 2). Sidebar selection lives in `AppState`.
struct MainWindowView: View {
    let appState: AppState
    let recorder: RecorderController

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(SidebarSection.allCases) { section in
                    Label {
                        HStack(spacing: 6) {
                            Text(section.displayName)
                            if let badge = section.badge {
                                Spacer(minLength: 0)
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    } icon: {
                        Image(systemName: section.systemImage)
                    }
                    .tag(section)
                }
            }
            .navigationTitle("Mengo")
            .frame(minWidth: 190)
        } detail: {
            switch appState.selectedSection {
            case .memory: MemoryPane(recorder: recorder)
            default:      ComingSoonPane(section: appState.selectedSection)
            }
        }
    }

    private var selectionBinding: Binding<SidebarSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { if let newValue = $0 { appState.selectedSection = newValue } }
        )
    }
}
```

- [ ] **Step 2: Update `MengoDesktopApp.swift`**

Replace `Sources/MengoDesktop/MengoDesktopApp.swift` with:

```swift
import SwiftUI
import AppKit

@main
@MainActor
struct MengoDesktopApp: App {
    @State private var appState = AppState()
    @State private var recorder = RecorderController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            MainWindowView(appState: appState, recorder: recorder)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 840, height: 560)

        MenuBarExtra {
            // MenuBarContent still has its Phase-1 init(appState:) here — Task 8
            // changes it to init(appState:recorder:) and the label below to MenuBarLabel.
            MenuBarContent(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Text("Mengo")
                Image(systemName: "circle.dotted")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Carries the lifecycle callbacks SwiftUI's scene phase doesn't reliably surface.
/// Starts the recorder on launch, stops it on quit. `sharedRecorder` is set by
/// `RecorderController.init()` (V1's bridge pattern).
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var sharedRecorder: RecorderController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await AppDelegate.sharedRecorder?.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.sharedRecorder?.stop()
            Log.line("app terminating")
        }
    }
}
```

- [ ] **Step 3: Build + full test suite**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all tests pass. (No real screenpipe is spawned by `swift test` — the tests use stubbed controllers.) After this task the app launches, starts the recorder, and shows the real `MemoryPane`; the menu's Memory group + the menu-bar label are still Phase-1-shaped (Task 8 finishes them).

- [ ] **Step 4: Commit**

```bash
git add Sources/MengoDesktop/MengoDesktopApp.swift Sources/MengoDesktop/MainWindowView.swift
git commit -m "MengoDesktop: thread RecorderController through app/window; start recorder on launch, stop on quit"
```

---

## Task 8: Wire the menu's Memory group + status-driven menu-bar label

**Files:**
- Modify: `Sources/MengoDesktop/MenuBarContent.swift`
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift`

- [ ] **Step 1: Replace `MenuBarContent.swift`**

Replace `Sources/MengoDesktop/MenuBarContent.swift` with:

```swift
import SwiftUI
import AppKit

/// The dropdown shown from the menu bar item. In Phase 2 the "Memory" group is
/// live (pause/resume, open folder/log, restart-on-error); the "Flow" group is
/// still disabled (Phase 3); Library/Studio/Settings navigate the main window.
struct MenuBarContent: View {
    let appState: AppState
    let recorder: RecorderController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Mengo").font(.headline)
        Divider()

        // MARK: Memory
        Text("Memory").font(.caption).foregroundStyle(.secondary)
        audioItem
        screenItem
        if case .error = recorder.status {
            Button("Restart recorder") { Task { await recorder.restartAfterCrash() } }
        }
        Button("Open data folder") { NSWorkspace.shared.open(recorder.dataFolderURL) }
        Button("Open recorder log") { NSWorkspace.shared.open(recorder.recorderLogURL) }

        // MARK: Flow (Phase 3)
        Text("Flow").font(.caption).foregroundStyle(.secondary)
        Button("Start recording…") { }.disabled(true)
        Button("Grab last 5 minutes…") { }.disabled(true)

        Divider()
        Button("Library") { reveal(.library) }
        Button(menuTitle(for: .studio)) { reveal(.studio) }
        Button("Settings…") { reveal(.settings) }

        Divider()
        Button("Quit Mengo Desktop") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var audioItem: some View {
        switch recorder.status {
        case .audioPaused, .bothPaused:
            Button("Resume audio") { Task { await recorder.resumeAudio() } }
        default:
            Button("Pause audio") { Task { await recorder.pauseAudio() } }
                .disabled(!recorder.status.isRecording)
        }
    }

    @ViewBuilder private var screenItem: some View {
        switch recorder.status {
        case .screenPaused, .bothPaused:
            Button("Resume screen") { Task { await recorder.resumeScreen() } }
        default:
            Button("Pause screen") { Task { await recorder.pauseScreen() } }
                .disabled(!recorder.status.isRecording)
        }
    }

    private func menuTitle(for section: SidebarSection) -> String {
        if let badge = section.badge { return "\(section.displayName) (\(badge))" }
        return section.displayName
    }

    private func reveal(_ section: SidebarSection) {
        appState.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The menu-bar item's label: "Mengo" plus a status-colored glyph.
struct MenuBarLabel: View {
    let status: RecorderStatus

    var body: some View {
        HStack(spacing: 4) {
            Text("Mengo")
            Image(systemName: glyph)
                .symbolRenderingMode(.palette)
                .foregroundStyle(color)
        }
    }

    private var glyph: String {
        switch status {
        case .recording: return "circle.fill"
        case .audioPaused, .screenPaused, .bothPaused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .starting, .idle: return "circle.dotted"
        }
    }
    private var color: Color {
        switch status {
        case .recording: return .green
        case .audioPaused, .screenPaused, .bothPaused: return .yellow
        case .error: return .red
        case .starting, .idle: return .secondary
        }
    }
}
```

- [ ] **Step 2: Update `MengoDesktopApp.swift` — pass `recorder` to the menu, use `MenuBarLabel`**

In `Sources/MengoDesktop/MengoDesktopApp.swift`, replace the entire `MenuBarExtra { … } label: { … }.menuBarExtraStyle(.menu)` block in `body` with:

```swift
        MenuBarExtra {
            MenuBarContent(appState: appState, recorder: recorder)
        } label: {
            MenuBarLabel(status: recorder.status)
        }
        .menuBarExtraStyle(.menu)
```

- [ ] **Step 3: Build + full test suite**

Run: `swift build --product MengoDesktop && swift test`
Expected: `Build complete!`; all tests pass.

- [ ] **Step 4: Commit**

```bash
git add Sources/MengoDesktop/MenuBarContent.swift Sources/MengoDesktop/MengoDesktopApp.swift
git commit -m "MengoDesktop: wire menu Memory group (pause/resume, open folder/log, restart) + status-driven menu-bar label"
```

---

## Task 9: `Info.plist` — TCC usage strings + local networking

**Files:**
- Modify: `Resources/MengoDesktopInfo.plist`

- [ ] **Step 1: Add the keys**

Edit `Resources/MengoDesktopInfo.plist`. Inside the top-level `<dict>`, after `NSHighResolutionCapable`, add:

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

- [ ] **Step 2: Verify the plist parses**

Run: `plutil -lint Resources/MengoDesktopInfo.plist`
Expected: `Resources/MengoDesktopInfo.plist: OK`

- [ ] **Step 3: Commit**

```bash
git add Resources/MengoDesktopInfo.plist
git commit -m "MengoDesktop: Info.plist — mic/screen/camera usage strings + NSAllowsLocalNetworking"
```

---

## Task 10: `build-mengo.sh` — bundle the screenpipe helper

**Files:**
- Modify: `build-mengo.sh`

- [ ] **Step 1: Add the screenpipe download + bundle + sign steps**

Replace `build-mengo.sh` with the following (it adds arch detection, the tarball download/cache into `.build-cache/`, extraction into `Contents/Helpers/`, and helper signing — adapted from V1's `build.sh` — on top of the existing Phase 1 script):

```bash
#!/usr/bin/env bash
set -euo pipefail

APP_NAME="MengoDesktop"
BUNDLE_ID="ai.mengo.desktop"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/$APP_NAME.app"
ZIP_OUT="$PROJECT_DIR/$APP_NAME.zip"
ICON_SRC="$PROJECT_DIR/Resources/AppIcon.png"
CACHE_DIR="$PROJECT_DIR/.build-cache"

cd "$PROJECT_DIR"

# screenpipe ships per-arch CLI packages on npm. Bundle the one matching this host.
HOST_ARCH=$(uname -m)
case "$HOST_ARCH" in
    arm64)  SP_ARCH="arm64" ;;
    x86_64) SP_ARCH="x64" ;;
    *) echo "unsupported arch: $HOST_ARCH"; exit 1 ;;
esac

echo "==> Resolving screenpipe latest version"
SP_VERSION=$(curl -fsSL https://registry.npmjs.org/screenpipe/latest \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['version'])")
SP_TARBALL_URL="https://registry.npmjs.org/@screenpipe/cli-darwin-$SP_ARCH/-/cli-darwin-$SP_ARCH-$SP_VERSION.tgz"
echo "    version: $SP_VERSION  arch: $SP_ARCH"

mkdir -p "$CACHE_DIR"
TARBALL="$CACHE_DIR/screenpipe-$SP_VERSION-$SP_ARCH.tgz"
if [ ! -f "$TARBALL" ]; then
    echo "==> Downloading screenpipe tarball"
    curl -fsSL "$SP_TARBALL_URL" -o "$TARBALL"
fi

echo "==> Building $APP_NAME (universal)"
swift build -c release --arch arm64 --arch x86_64 --product "$APP_NAME"

echo "==> Assembling .app bundle"
rm -rf "$APP_BUNDLE" "$ZIP_OUT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"
mkdir -p "$APP_BUNDLE/Contents/Helpers"

cp ".build/apple/Products/Release/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/MengoDesktopInfo.plist "$APP_BUNDLE/Contents/Info.plist"

# Embed the screenpipe binary + its Metal library. Tarball layout: package/bin/{screenpipe, mlx.metallib}
tar -xzf "$TARBALL" -C "$APP_BUNDLE/Contents/Helpers" --strip-components=2 package/bin/
chmod +x "$APP_BUNDLE/Contents/Helpers/screenpipe"

# Generate AppIcon.icns from the committed source PNG.
if [ -f "$ICON_SRC" ]; then
    echo "==> Generating AppIcon.icns from Resources/AppIcon.png"
    TMPDIR_ICON="$(mktemp -d)"
    ICONSET="$TMPDIR_ICON/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png"      >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png"      >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png"    >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png"    >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png"    >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$TMPDIR_ICON"
else
    echo "WARNING: $ICON_SRC not found — building without a custom app icon"
fi

# Signing. Prefer the self-signed dev cert (stable identity across rebuilds → TCC
# grants survive; the bundled helper inherits them), else ad-hoc. The helper gets
# the SAME identifier as the .app so macOS treats it as part of Mengo Desktop.
CERT_NAME="ScreenpipeMenu Local Dev"
CERT_LINE=$(security find-identity -p basic login.keychain 2>/dev/null | grep "$CERT_NAME" || true)
CERT_SHA=$(echo "$CERT_LINE" | awk '{print $2}' | head -1)
if [ -n "$CERT_SHA" ]; then
    SIGN_IDENTITY="$CERT_SHA"
    echo "==> Codesigning with '$CERT_NAME' ($CERT_SHA)"
else
    SIGN_IDENTITY="-"
    echo "==> Codesigning ad-hoc (run ./bootstrap-cert.sh once for stable signing)"
fi

codesign --remove-signature "$APP_BUNDLE/Contents/Helpers/screenpipe" 2>/dev/null || true
codesign --sign "$SIGN_IDENTITY" --force "$APP_BUNDLE/Contents/Helpers/mlx.metallib"
codesign --sign "$SIGN_IDENTITY" --force --identifier "$BUNDLE_ID" "$APP_BUNDLE/Contents/Helpers/screenpipe"
codesign --sign "$SIGN_IDENTITY" --force --identifier "$BUNDLE_ID" "$APP_BUNDLE"

echo "==> Zipping for distribution"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_OUT"

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
ZIP_SIZE=$(du -sh "$ZIP_OUT" | cut -f1)
echo
echo "Done."
echo "  screenpipe v$SP_VERSION ($SP_ARCH) embedded"
echo "  App:  $APP_BUNDLE ($APP_SIZE)"
echo "  Zip:  $ZIP_OUT ($ZIP_SIZE)"
```

(`.build-cache/` is already in `.gitignore`; no `.gitignore` change.)

- [ ] **Step 2: Run it**

Run: `./build-mengo.sh`
Expected: ends with `Done.` and `screenpipe vX.Y.Z (arm64) embedded` + the app/zip paths.

> **Sandbox note:** if the environment blocks the `curl https://registry.npmjs.org/...` calls, the download step fails. In that case: the `build-mengo.sh` changes are committed regardless (Step 3); note in the commit/PR that a full bundled `.app` must be built on a machine with network access; and skip the verification in Step 4 (do it on that machine).

- [ ] **Step 3: Verify the bundle (if Step 2 ran)**

```bash
test -f MengoDesktop.app/Contents/Helpers/screenpipe && echo "helper OK"
test -f MengoDesktop.app/Contents/Helpers/mlx.metallib && echo "metallib OK"
codesign -dv MengoDesktop.app/Contents/Helpers/screenpipe 2>&1 | grep Identifier
codesign -dv MengoDesktop.app 2>&1 | grep Identifier
```
Expected: `helper OK`, `metallib OK`, and both `Identifier=ai.mengo.desktop`.

- [ ] **Step 4: Commit**

```bash
git add build-mengo.sh
git commit -m "build-mengo.sh: bundle the screenpipe helper (build-time download, signed with the app identifier for TCC inheritance)"
```

---

## Task 11: Manual smoke-test checklist + run the scriptable part

**Files:**
- Create: `docs/manual-smoke-tests/mengo-phase-2-memory.md`

- [ ] **Step 1: Create the checklist doc**

Create `docs/manual-smoke-tests/mengo-phase-2-memory.md`:

```markdown
# Manual Smoke Test — Mengo Desktop Phase 2 ("Mengo Memory")

Run before tagging `mengo-v2-phase-2-memory`. Spec:
`docs/superpowers/specs/2026-05-12-mengo-phase-2-memory-design.md`.

## Build & tests (scriptable)

- [ ] `swift build` — all targets compile.
- [ ] `swift test` — all tests pass (Phase 1's + Phase 2's).
- [ ] `./build-mengo.sh` — completes; prints `screenpipe vX.Y.Z (arch) embedded`; produces `MengoDesktop.app` + `.zip`. (Needs network for the screenpipe download.)
- [ ] `MengoDesktop.app/Contents/Helpers/{screenpipe,mlx.metallib}` exist; both codesigned with `Identifier=ai.mengo.desktop` (`codesign -dv`).
- [ ] `Info.plist` has `NSMicrophoneUsageDescription`, `NSScreenCaptureUsageDescription`, `NSAllowsLocalNetworking`; `LSUIElement = false`.

## App behaviour (run `open MengoDesktop.app` — needs a human at the machine)

- [ ] Screen Recording + Microphone permission dialogs appear; grant both (toggle Mengo Desktop on in System Settings if prompted).
- [ ] Within ~15 s the menu-bar glyph turns **green** and the Memory pane shows "● Recording" + `screenpipe vX.Y.Z`.
- [ ] `~/.screenpipe/` starts filling with data; `~/Library/Logs/MengoDesktop/recorder.log` has screenpipe output.
- [ ] Menu **Pause audio** → glyph yellow, pane shows "Audio paused"; **Resume audio** → green again.
- [ ] Menu **Pause screen** → `pgrep screenpipe` shows the process gone, glyph yellow, pane "Screen paused"; **Resume screen** → process back, glyph green.
- [ ] **Open data folder** opens `~/.screenpipe/`; **Open recorder log** opens `recorder.log` (menu and Memory pane both work).
- [ ] `pkill screenpipe` → within ~30 s glyph **red**, pane shows the error + a **Restart recorder** button; clicking it (or the menu "Restart recorder") brings it back to green.
- [ ] Close the main window → app stays in the Dock, glyph still green (recording continues).
- [ ] **Quit** (⌘Q / menu) → app exits; `pgrep screenpipe` shows no orphan; `~/Library/Logs/MengoDesktop/app.log` has `app terminating`.
```

- [ ] **Step 2: Run the scriptable portion**

```bash
swift build
swift test
./build-mengo.sh   # if the sandbox blocks the npm download, note it and skip the bundle checks
codesign -dv MengoDesktop.app/Contents/Helpers/screenpipe 2>&1 | grep Identifier || true
```
Expected: build complete, all tests pass, build script done (network permitting), helper identifier `ai.mengo.desktop`.

- [ ] **Step 3: Run the app-behaviour portion**

Run `open MengoDesktop.app` and walk the "App behaviour" checkboxes (needs a human at the machine, or the computer-use tools). Fix anything that fails and re-run the relevant earlier task. Quit any leftover `screenpipe` (`pkill screenpipe`) and the app afterward.

- [ ] **Step 4: Commit the checklist**

```bash
git add docs/manual-smoke-tests/mengo-phase-2-memory.md
git commit -m "MengoDesktop: Phase 2 manual smoke-test checklist"
```

- [ ] **Step 5: (Optional) tag the phase release once the checklist passes**

```bash
git tag mengo-v2-phase-2-memory
```

---

## Done criteria

- `swift build` / `swift test` pass; `./build-mengo.sh` (with network) produces a `MengoDesktop.app` with a codesigned `Contents/Helpers/screenpipe`.
- Launching the app starts screenpipe (after the TCC grants), the menu-bar glyph reflects recorder status (green/yellow/red), the Memory pane shows status + controls + health + crash-recovery, and Quit cleanly stops the helper.
- `Sources/ScreenpipeMenu/` and `Sources/ScreenpipeFlow/` are untouched; only `MengoDesktop` files, `Resources/MengoDesktopInfo.plist`, and `build-mengo.sh` changed.
- The Phase 2 manual smoke checklist passes.
