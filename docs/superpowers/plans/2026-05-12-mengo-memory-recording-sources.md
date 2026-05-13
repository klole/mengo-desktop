# Mengo Memory — recording-source picker + pane polish — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "Recording sources" sheet to the Memory pane (pick which displays/microphones screenpipe records, with an explicit "Apply & restart"), and finish the redesigned pane's polish — fix the blank Pause-screen icon, drop the "View log" link, equalise the session-tile heights, recolour the blue accents to brand orange.

**Architecture:** New `SourceCatalog` shells out to the bundled `screenpipe vision list / audio list` to enumerate hardware; `RecordingSourcesStore` persists the user's pick in `UserDefaults` (`nil` = screenpipe default = today's behaviour); `RecorderController` translates the pick into `--monitor-id` / `--audio-device` / `--disable-audio` args at spawn time and gains `applyRecordingSources()` which restarts the recorder. `RecordingSourcesView` is the System-Settings-Displays-style sheet. `RecorderProcessControlling.start` grows an `extraArguments:` parameter. The polish items are local SwiftUI edits in `MemoryPane.swift` / `MenuBarContent.swift` / `MainWindowView.swift`.

**Tech Stack:** Swift 6, SwiftUI, `@Observable` `@MainActor`, XCTest. macOS 15+. Bundled `screenpipe` helper at `Contents/Helpers/screenpipe`.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-memory-recording-sources-design.md`](../specs/2026-05-12-mengo-memory-recording-sources-design.md)

**Branch:** `claude/kind-volhard-f7e189` (already off `main` at `a8a37e4`; this is the worktree at `.claude/worktrees/kind-volhard-f7e189`).

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/SourceCatalog.swift` | **new** | `MonitorInfo` / `AudioDeviceInfo` value types; pure `decode…(from: Data)` functions; `RecordingSourceCatalog` protocol + `ScreenpipeCLICatalog` impl that runs `screenpipe vision list -o json` / `audio list -o json` off the main actor. |
| `Sources/MengoDesktop/RecordingSourcesStore.swift` | **new** | `UserDefaults` wrapper: `selectedMonitorIDs: [Int]?`, `selectedAudioDeviceNames: [String]?` (`nil` unset / `[]` distinct), injectable `UserDefaults`. |
| `Sources/MengoDesktop/RecordingSourcesView.swift` | **new** | The sheet: spinner → display thumbnails (tap to include, orange ring) + audio toggle list → "Apply & restart" footer. |
| `Sources/MengoDesktop/RecorderProcess.swift` | modify | `RecorderProcessControlling.start(binaryURL:extraArguments:)`; `RecorderProcess` appends the extra args. |
| `Sources/MengoDesktop/RecorderController.swift` | modify | Inject store + catalog; build source args before each spawn; `runningMonitorIDs` / `runningAudioDeviceNames` / `runningAudioDisabled`; `applyRecordingSources()`. |
| `Sources/MengoDesktop/MemoryPane.swift` | modify | "Configure sources…" button + `.sheet`; fix Pause-screen `systemImage`; remove footer "View log"; degraded-banner copy; `StatTile` two-line label reservation; tiles read running config. |
| `Sources/MengoDesktop/MenuBarContent.swift` | modify | Fix the same `display.slash` in `screenItem`. |
| `Sources/MengoDesktop/MainWindowView.swift` | modify | Sidebar selected-row highlight → brand orange. |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | modify | Pass a `RecordingSourcesStore` + `SourceCatalog` into `RecorderController()` (or rely on defaults — see Task 6). |
| `Tests/MengoDesktopTests/SourceCatalogTests.swift` | **new** | decode tests. |
| `Tests/MengoDesktopTests/RecordingSourcesStoreTests.swift` | **new** | round-trip tests. |
| `Tests/MengoDesktopTests/RecorderControllerTests.swift` | modify | new `StubProcess.start` signature; arg-building tests; `applyRecordingSources` test; inject a `StubCatalog` + in-memory `RecordingSourcesStore`. |
| `Tests/MengoDesktopTests/RecorderProcessTests.swift` | (no change — only tests `newToken`) |
| `docs/manual-smoke-tests/mengo-phase-2-memory.md` | modify | "Recording sources" section + polish checks. |

---

## Task 1: Polish — Pause-screen icon, remove "View log", equal-height tiles, degraded copy

**Files:**
- Modify: `Sources/MengoDesktop/MemoryPane.swift`
- Modify: `Sources/MengoDesktop/MenuBarContent.swift`

No automated tests (no SwiftUI view tests in this repo). Verify by `swift build` + relaunch later (Task 9).

- [ ] **Step 1: Fix the Pause-screen icon in `MemoryPane.swift`.** In `controls`, the screen button currently uses `systemImage: screenPausedNow ? "display" : "display.slash"` — `display.slash` is not a real SF Symbol (renders blank). Change to:

```swift
Button { Task { await screenAction() } } label: {
    Label(screenTitle, systemImage: screenPausedNow ? "rectangle" : "rectangle.slash")
}
.buttonStyle(.bordered).disabled(disableControls)
```

(If `rectangle.slash` looks wrong at build time, the documented fallback is `eye.slash` / `eye` — both exist on macOS 15 and read as "stop/resume watching the screen". Pick one and use it consistently in this file and `MenuBarContent.swift`.)

- [ ] **Step 2: Fix the same symbol in `MenuBarContent.swift`.** In `screenItem`, the default case uses `Label("Pause screen", systemImage: "display.slash")` and the paused case uses `"display"`. Make them match the pane:

```swift
@ViewBuilder private var screenItem: some View {
    switch recorder.status {
    case .screenPaused, .bothPaused:
        Button { Task { await recorder.resumeScreen() } } label: { Label("Resume screen", systemImage: "rectangle") }
    default:
        Button { Task { await recorder.pauseScreen() } } label: { Label("Pause screen", systemImage: "rectangle.slash") }
            .disabled(!recorder.status.isRecording)
    }
}
```

- [ ] **Step 3: Remove the footer "View log" link in `MemoryPane.swift`.** Replace the `footer` computed property with the privacy line only:

```swift
private var footer: some View {
    Text("Mengo Memory keeps a private, on-device record of what you see and hear. Nothing is uploaded.")
        .font(Theme.caption).foregroundStyle(Theme.mutedText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
}
```

(The recorder log stays reachable from the menu-bar dropdown's "View log" item, which is untouched.)

- [ ] **Step 4: Soften the degraded-banner copy in `MemoryPane.swift`.** In `degradedMessage`, drop the "open the log for details" tail:

```swift
private var degradedMessage: String? {
    guard recorder.status == .recording, let h = recorder.lastHealth else { return nil }
    if h.frameStatus != "ok" { return "Screen capture is degraded." }
    if h.audioStatus != "ok" { return "Microphone capture is degraded." }
    return nil
}
```

- [ ] **Step 5: Equalise the `StatTile` heights in `MemoryPane.swift`.** In `private struct StatTile`, the label currently uses `.fixedSize()` which makes the one-line "displays" tile shorter. Replace the label line:

```swift
Text(label).font(.system(size: 10)).foregroundStyle(Theme.mutedText)
    .multilineTextAlignment(.center)
    .lineLimit(2, reservesSpace: true)
    .fixedSize(horizontal: true, vertical: false)
```

- [ ] **Step 6: Build.** Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 7: Commit.**

```bash
git add Sources/MengoDesktop/MemoryPane.swift Sources/MengoDesktop/MenuBarContent.swift
git commit -m "MengoDesktop: Memory pane polish — Pause-screen icon, drop 'View log', equal-height stat tiles, terser degraded copy"
```

---

## Task 2: Polish — recolour blue accents to brand orange

**Files:**
- Modify: `Sources/MengoDesktop/MainWindowView.swift`
- Modify: `Sources/MengoDesktop/MemoryPane.swift`

- [ ] **Step 1: Make in-pane link buttons orange in `MemoryPane.swift`.** SwiftUI's `.buttonStyle(.link)` renders in the system link colour (blue). Replace it. In `controls`, the "Reveal recordings" button:

```swift
Button { NSWorkspace.shared.open(recorder.dataFolderURL) } label: {
    Label("Reveal recordings", systemImage: "folder")
}
.buttonStyle(.plain).foregroundStyle(Theme.accent)
```

(The "Configure sources…" button added in Task 7 uses the same treatment.)

- [ ] **Step 2: Force the sidebar selection orange in `MainWindowView.swift`.** macOS sidebar `List(selection:)` highlights with the *system* accent and ignores SwiftUI `.tint`. Replace the `List` in `body` with a manually-highlighted list of rows:

```swift
var body: some View {
    NavigationSplitView {
        VStack(spacing: 0) {
            wordmark
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(SidebarSection.allCases) { section in
                        sidebarRow(section)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
        .background(Theme.windowBackground)
        .frame(minWidth: 200)
    } detail: {
        Group {
            switch appState.selectedSection {
            case .memory: MemoryPane(recorder: recorder)
            default:      ComingSoonPane(section: appState.selectedSection)
            }
        }
        .id(appState.selectedSection)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.22), value: appState.selectedSection)
    }
}

private func sidebarRow(_ section: SidebarSection) -> some View {
    let selected = appState.selectedSection == section
    return Button {
        appState.selectedSection = section
    } label: {
        HStack(spacing: 8) {
            Image(systemName: section.systemImage)
                .frame(width: 18)
                .foregroundStyle(selected ? Color.white : Theme.secondaryText)
            Text(section.displayName)
                .foregroundStyle(selected ? Color.white : Theme.primaryText)
            if let badge = section.badge {
                Spacer(minLength: 0)
                Text(badge).font(.caption2.weight(.semibold))
                    .foregroundStyle(selected ? Color.white.opacity(0.8) : Theme.mutedText)
            } else {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Theme.accent : Color.clear)
        )
    }
    .buttonStyle(.plain)
}
```

Delete the now-unused `selectionBinding` computed property. Keep `wordmark` as-is.

- [ ] **Step 3: Build.** Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit.**

```bash
git add Sources/MengoDesktop/MainWindowView.swift Sources/MengoDesktop/MemoryPane.swift
git commit -m "MengoDesktop: recolour blue accents to brand orange (sidebar selection, in-pane links)"
```

---

## Task 3: `SourceCatalog` — enumerate displays + audio devices

**Files:**
- Create: `Sources/MengoDesktop/SourceCatalog.swift`
- Test: `Tests/MengoDesktopTests/SourceCatalogTests.swift`

- [ ] **Step 1: Write the failing tests** in `Tests/MengoDesktopTests/SourceCatalogTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class SourceCatalogTests: XCTestCase {

    func test_decodeMonitors_parsesData() throws {
        let json = Data("""
        { "data": [
            { "id": 1, "name": "Display 1", "width": 1728, "height": 1117, "is_default": true },
            { "id": 2, "name": "Display 2", "width": 3440, "height": 1440, "is_default": false }
        ], "success": true }
        """.utf8)
        let monitors = try SourceCatalog.decodeMonitors(from: json)
        XCTAssertEqual(monitors.count, 2)
        XCTAssertEqual(monitors[0].id, 1)
        XCTAssertEqual(monitors[0].name, "Display 1")
        XCTAssertEqual(monitors[0].width, 1728)
        XCTAssertEqual(monitors[0].height, 1117)
        XCTAssertTrue(monitors[0].isDefault)
        XCTAssertFalse(monitors[1].isDefault)
    }

    func test_decodeAudioDevices_parsesKindAndDisplayName() throws {
        let json = Data("""
        { "data": [
            { "name": "MacBook Pro Microphone (input)", "is_default": false },
            { "name": "System Audio (output)", "is_default": true },
            { "name": "Weird Device", "is_default": false }
        ], "success": true }
        """.utf8)
        let devices = try SourceCatalog.decodeAudioDevices(from: json)
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].name, "MacBook Pro Microphone (input)")
        XCTAssertEqual(devices[0].displayName, "MacBook Pro Microphone")
        XCTAssertEqual(devices[0].kind, .input)
        XCTAssertEqual(devices[1].displayName, "System Audio")
        XCTAssertEqual(devices[1].kind, .output)
        XCTAssertTrue(devices[1].isDefault)
        XCTAssertEqual(devices[2].displayName, "Weird Device")
        XCTAssertEqual(devices[2].kind, .unknown)
    }

    func test_decode_throwsOnMalformedBody() {
        XCTAssertThrowsError(try SourceCatalog.decodeMonitors(from: Data("not json".utf8)))
        XCTAssertThrowsError(try SourceCatalog.decodeAudioDevices(from: Data(#"{"success":true}"#.utf8)))
    }
}
```

- [ ] **Step 2: Run, verify it fails.** Run: `swift test --filter SourceCatalogTests`
Expected: FAIL — `SourceCatalog` not found.

- [ ] **Step 3: Implement** `Sources/MengoDesktop/SourceCatalog.swift`:

```swift
import Foundation

/// A display screenpipe can record. From `screenpipe vision list -o json`.
struct MonitorInfo: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    let isDefault: Bool
}

/// An audio device screenpipe can record. From `screenpipe audio list -o json`.
/// `name` is what screenpipe wants on the command line (suffix included);
/// `displayName` strips the trailing `(input)`/`(output)` for the UI.
struct AudioDeviceInfo: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case input, output, unknown }
    let name: String
    let isDefault: Bool
    var id: String { name }
    var kind: Kind {
        if name.hasSuffix("(input)") { return .input }
        if name.hasSuffix("(output)") { return .output }
        return .unknown
    }
    var displayName: String {
        for suffix in [" (input)", " (output)", "(input)", "(output)"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return name
    }
}

/// Enumerates the displays / audio devices available to record. Implementations
/// must be safe to call when the recorder isn't running.
protocol RecordingSourceCatalog: Sendable {
    func availableMonitors() async throws -> [MonitorInfo]
    func availableAudioDevices() async throws -> [AudioDeviceInfo]
}

/// Shells out to the bundled `screenpipe` helper's `vision list` / `audio list`
/// subcommands (JSON output). Runs the subprocess off the main actor.
struct ScreenpipeCLICatalog: RecordingSourceCatalog {
    var binaryURL: () throws -> URL = { try BinaryManager.ensureBinary() }

    func availableMonitors() async throws -> [MonitorInfo] {
        let data = try await runJSON(["vision", "list", "-o", "json"])
        return try SourceCatalog.decodeMonitors(from: data)
    }
    func availableAudioDevices() async throws -> [AudioDeviceInfo] {
        let data = try await runJSON(["audio", "list", "-o", "json"])
        return try SourceCatalog.decodeAudioDevices(from: data)
    }

    private func runJSON(_ args: [String]) async throws -> Data {
        let url = try binaryURL()
        return try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = url
            proc.arguments = args
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            proc.environment = env
            let out = Pipe(); proc.standardOutput = out
            proc.standardError = Pipe()
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return data
        }.value
    }
}

/// Pure decoders — split out so tests don't need a subprocess.
enum SourceCatalog {
    private struct MonitorsResponse: Decodable {
        struct Item: Decodable { let id: Int; let name: String; let width: Int; let height: Int; let is_default: Bool }
        let data: [Item]
    }
    private struct AudioResponse: Decodable {
        struct Item: Decodable { let name: String; let is_default: Bool }
        let data: [Item]
    }

    static func decodeMonitors(from data: Data) throws -> [MonitorInfo] {
        try JSONDecoder().decode(MonitorsResponse.self, from: data).data.map {
            MonitorInfo(id: $0.id, name: $0.name, width: $0.width, height: $0.height, isDefault: $0.is_default)
        }
    }
    static func decodeAudioDevices(from data: Data) throws -> [AudioDeviceInfo] {
        try JSONDecoder().decode(AudioResponse.self, from: data).data.map {
            AudioDeviceInfo(name: $0.name, isDefault: $0.is_default)
        }
    }
}
```

- [ ] **Step 4: Run, verify pass.** Run: `swift test --filter SourceCatalogTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit.**

```bash
git add Sources/MengoDesktop/SourceCatalog.swift Tests/MengoDesktopTests/SourceCatalogTests.swift
git commit -m "MengoDesktop: SourceCatalog — enumerate displays/audio devices via bundled screenpipe (TDD)"
```

---

## Task 4: `RecordingSourcesStore` — persist the user's pick

**Files:**
- Create: `Sources/MengoDesktop/RecordingSourcesStore.swift`
- Test: `Tests/MengoDesktopTests/RecordingSourcesStoreTests.swift`

- [ ] **Step 1: Write the failing tests** in `Tests/MengoDesktopTests/RecordingSourcesStoreTests.swift`:

```swift
import XCTest
@testable import MengoDesktop

final class RecordingSourcesStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "MengoTest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_defaults_areNil() {
        let store = RecordingSourcesStore(defaults: freshDefaults())
        XCTAssertNil(store.selectedMonitorIDs)
        XCTAssertNil(store.selectedAudioDeviceNames)
    }

    func test_monitorIDs_roundTrip_includingEmpty() {
        let store = RecordingSourcesStore(defaults: freshDefaults())
        store.selectedMonitorIDs = [1, 2]
        XCTAssertEqual(store.selectedMonitorIDs, [1, 2])
        store.selectedMonitorIDs = []
        XCTAssertEqual(store.selectedMonitorIDs, [])     // empty, not nil
        store.selectedMonitorIDs = nil
        XCTAssertNil(store.selectedMonitorIDs)
    }

    func test_audioNames_roundTrip_emptyDistinctFromNil() {
        let store = RecordingSourcesStore(defaults: freshDefaults())
        XCTAssertNil(store.selectedAudioDeviceNames)
        store.selectedAudioDeviceNames = []
        XCTAssertEqual(store.selectedAudioDeviceNames, [])
        store.selectedAudioDeviceNames = ["MacBook Pro Microphone (input)"]
        XCTAssertEqual(store.selectedAudioDeviceNames, ["MacBook Pro Microphone (input)"])
        store.selectedAudioDeviceNames = nil
        XCTAssertNil(store.selectedAudioDeviceNames)
    }

    func test_persistsAcrossInstances() {
        let d = freshDefaults()
        RecordingSourcesStore(defaults: d).selectedMonitorIDs = [3]
        XCTAssertEqual(RecordingSourcesStore(defaults: d).selectedMonitorIDs, [3])
    }
}
```

- [ ] **Step 2: Run, verify it fails.** Run: `swift test --filter RecordingSourcesStoreTests`
Expected: FAIL — `RecordingSourcesStore` not found.

- [ ] **Step 3: Implement** `Sources/MengoDesktop/RecordingSourcesStore.swift`:

```swift
import Foundation

/// Persists which displays / microphones the user wants recorded.
///
/// `nil` means "leave it to screenpipe's default" — all monitors / default mic +
/// system audio — so an untouched install records exactly as it ships. An
/// explicitly **empty** `selectedAudioDeviceNames` means "no audio" (`--disable-audio`),
/// which is why it's stored distinctly from `nil`. Monitor IDs are re-validated
/// against the live display list at spawn time (see `RecorderController`).
struct RecordingSourcesStore {
    private let defaults: UserDefaults
    private let monitorKey = "recording.selectedMonitorIDs"
    private let audioKey = "recording.selectedAudioDeviceNames"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var selectedMonitorIDs: [Int]? {
        get { defaults.array(forKey: monitorKey) as? [Int] }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: monitorKey) }
            else { defaults.removeObject(forKey: monitorKey) }
        }
    }

    var selectedAudioDeviceNames: [String]? {
        get { defaults.array(forKey: audioKey) as? [String] }
        nonmutating set {
            if let newValue { defaults.set(newValue, forKey: audioKey) }
            else { defaults.removeObject(forKey: audioKey) }
        }
    }
}
```

- [ ] **Step 4: Run, verify pass.** Run: `swift test --filter RecordingSourcesStoreTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit.**

```bash
git add Sources/MengoDesktop/RecordingSourcesStore.swift Tests/MengoDesktopTests/RecordingSourcesStoreTests.swift
git commit -m "MengoDesktop: RecordingSourcesStore — persist selected displays/mics in UserDefaults (TDD)"
```

---

## Task 5: `RecorderProcessControlling.start` gains `extraArguments:`

**Files:**
- Modify: `Sources/MengoDesktop/RecorderProcess.swift`
- Modify: `Sources/MengoDesktop/RecorderController.swift` (call sites)
- Modify: `Tests/MengoDesktopTests/RecorderControllerTests.swift` (`StubProcess`)

- [ ] **Step 1: Change the protocol + impl** in `RecorderProcess.swift`:

```swift
protocol RecorderProcessControlling: AnyObject {
    var isRunning: Bool { get }
    func start(binaryURL: URL, extraArguments: [String]) throws
    func stop()
}
```

In `RecorderProcess.start`, change the signature and the `arguments` line:

```swift
func start(binaryURL: URL, extraArguments: [String]) throws {
    guard !isRunning else { return }
    FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
    let handle = try FileHandle(forWritingTo: logFileURL)
    self.logHandle = handle

    let proc = Process()
    proc.executableURL = binaryURL
    proc.arguments = ["record"] + extraArguments
    // … (rest unchanged: env, PATH, standardOutput/Error, run) …
}
```

- [ ] **Step 2: Update the three call sites in `RecorderController.swift`** to pass `extraArguments:` — for now pass `[]` everywhere (Task 6 replaces these with the real args). The call sites are in `spawnAndPoll(binaryURL:)`, `resumeScreen()`, and `restartAfterCrash()` (via `spawnAndPoll`). So really two: `try process.start(binaryURL: binaryURL)` → `try process.start(binaryURL: binaryURL, extraArguments: [])` in `spawnAndPoll`, and the same in `resumeScreen()`.

- [ ] **Step 3: Update `StubProcess` in `RecorderControllerTests.swift`:**

```swift
final class StubProcess: RecorderProcessControlling {
    var running = false
    var shouldFailStart = false
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastExtraArguments: [String] = []
    var isRunning: Bool { running }
    func start(binaryURL: URL, extraArguments: [String]) throws {
        if shouldFailStart { throw StubError.boom }
        startCount += 1; running = true; lastExtraArguments = extraArguments
    }
    func stop() { stopCount += 1; running = false }
}
```

- [ ] **Step 4: Build + run the existing suite.** Run: `swift build && swift test --filter MengoDesktopTests`
Expected: `Build complete!` then all existing MengoDesktop tests PASS (the signature change is mechanical).

- [ ] **Step 5: Commit.**

```bash
git add Sources/MengoDesktop/RecorderProcess.swift Sources/MengoDesktop/RecorderController.swift Tests/MengoDesktopTests/RecorderControllerTests.swift
git commit -m "MengoDesktop: RecorderProcessControlling.start takes extraArguments (no-op wiring)"
```

---

## Task 6: `RecorderController` — build source args + `applyRecordingSources()`

**Files:**
- Modify: `Sources/MengoDesktop/RecorderController.swift`
- Modify: `Sources/MengoDesktop/MengoDesktopApp.swift` (inject real store/catalog — or leave defaults; see Step 4)
- Test: `Tests/MengoDesktopTests/RecorderControllerTests.swift`

- [ ] **Step 1: Write the failing tests.** Add to `RecorderControllerTests.swift`:

```swift
// A stub catalog with a fixed monitor/device list.
struct StubCatalog: RecordingSourceCatalog {
    var monitors: [MonitorInfo]
    var devices: [AudioDeviceInfo] = []
    func availableMonitors() async throws -> [MonitorInfo] { monitors }
    func availableAudioDevices() async throws -> [AudioDeviceInfo] { devices }
}

private func freshStore() -> RecordingSourcesStore {
    let name = "MengoTest-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
    return RecordingSourcesStore(defaults: d)
}

// Extend makeController to accept store + catalog (defaults keep existing tests working):
private func makeController(process: StubProcess = StubProcess(),
                           api: StubAPI = StubAPI(),
                           store: RecordingSourcesStore? = nil,
                           catalog: RecordingSourceCatalog = StubCatalog(monitors: []),
                           ensureBinary: @escaping () throws -> URL = { URL(fileURLWithPath: "/tmp/fake-screenpipe") })
    -> RecorderController {
    RecorderController(
        processFactory: { _ in process },
        apiFactory: { _ in api },
        ensureBinary: ensureBinary,
        requestPermissions: { },
        pollInterval: .milliseconds(1),
        sourcesStore: store ?? freshStore(),
        sourceCatalog: catalog
    )
}

func test_sourceArgs_nilSelection_noMonitorFlags_andCatalogNotConsulted() async {
    final class CountingCatalog: RecordingSourceCatalog {
        var monitorCalls = 0
        func availableMonitors() async throws -> [MonitorInfo] { monitorCalls += 1; return [] }
        func availableAudioDevices() async throws -> [AudioDeviceInfo] { [] }
    }
    let proc = StubProcess(); let cat = CountingCatalog()
    let c = makeController(process: proc, catalog: cat)   // store left nil → all defaults
    await c.start()
    await eventually { c.status == .recording }
    XCTAssertFalse(proc.lastExtraArguments.contains("--monitor-id"))
    XCTAssertFalse(proc.lastExtraArguments.contains("--disable-audio"))
    XCTAssertEqual(cat.monitorCalls, 0)
}

func test_sourceArgs_explicitMonitors_emittedAndValidated() async {
    let store = freshStore(); store.selectedMonitorIDs = [1, 9]    // 9 isn't live
    let proc = StubProcess()
    let cat = StubCatalog(monitors: [MonitorInfo(id: 1, name: "D1", width: 100, height: 100, isDefault: true)])
    let c = makeController(process: proc, store: store, catalog: cat)
    await c.start()
    await eventually { c.status == .recording }
    XCTAssertEqual(proc.lastExtraArguments, ["--monitor-id", "1"])   // 9 dropped
}

func test_sourceArgs_emptyMonitorsAfterValidation_fallsBackToAll() async {
    let store = freshStore(); store.selectedMonitorIDs = [42]       // none live
    let proc = StubProcess()
    let cat = StubCatalog(monitors: [MonitorInfo(id: 1, name: "D1", width: 1, height: 1, isDefault: true)])
    let c = makeController(process: proc, store: store, catalog: cat)
    await c.start()
    await eventually { c.status == .recording }
    XCTAssertFalse(proc.lastExtraArguments.contains("--monitor-id"))
}

func test_sourceArgs_emptyAudio_disablesAudio() async {
    let store = freshStore(); store.selectedAudioDeviceNames = []
    let proc = StubProcess()
    let c = makeController(process: proc, store: store)
    await c.start()
    await eventually { c.status == .recording }
    XCTAssertTrue(proc.lastExtraArguments.contains("--disable-audio"))
    XCTAssertTrue(c.runningAudioDisabled)
}

func test_sourceArgs_explicitAudioDevices_emitted() async {
    let store = freshStore(); store.selectedAudioDeviceNames = ["Mic A (input)", "System Audio (output)"]
    let proc = StubProcess()
    let c = makeController(process: proc, store: store)
    await c.start()
    await eventually { c.status == .recording }
    XCTAssertEqual(proc.lastExtraArguments,
                   ["--audio-device", "Mic A (input)", "--audio-device", "System Audio (output)"])
}

func test_applyRecordingSources_restartsWithNewArgs() async {
    let store = freshStore()
    let proc = StubProcess()
    let cat = StubCatalog(monitors: [
        MonitorInfo(id: 1, name: "D1", width: 1, height: 1, isDefault: true),
        MonitorInfo(id: 2, name: "D2", width: 1, height: 1, isDefault: false),
    ])
    let c = makeController(process: proc, store: store, catalog: cat)
    await c.start()
    await eventually { c.status == .recording }
    let startsBefore = proc.startCount
    store.selectedMonitorIDs = [2]
    store.selectedAudioDeviceNames = []
    await c.applyRecordingSources()
    await eventually { c.status == .recording }
    XCTAssertEqual(proc.startCount, startsBefore + 1)
    XCTAssertEqual(proc.lastExtraArguments, ["--monitor-id", "2", "--disable-audio"])
    XCTAssertEqual(c.runningMonitorIDs, [2])
    XCTAssertTrue(c.runningAudioDisabled)
}
```

- [ ] **Step 2: Run, verify it fails.** Run: `swift test --filter RecorderControllerTests`
Expected: FAIL — `RecorderController.init` has no `sourcesStore:` param; `runningAudioDisabled` / `runningMonitorIDs` / `applyRecordingSources` missing.

- [ ] **Step 3: Implement in `RecorderController.swift`.**

(a) New stored deps + observable "running" state. Add after the existing `@ObservationIgnored` block / `recordingsSizeBytes`:

```swift
private(set) var runningMonitorIDs: [Int]?      // nil = all monitors
private(set) var runningAudioDeviceNames: [String]?  // nil = screenpipe default
private(set) var runningAudioDisabled = false

@ObservationIgnored private let sourcesStore: RecordingSourcesStore
@ObservationIgnored private let sourceCatalog: RecordingSourceCatalog
```

(b) Extend `init` with two new parameters (with defaults so production callers need no change):

```swift
init(
    processFactory: (String) -> RecorderProcessControlling = { RecorderProcess(token: $0) },
    apiFactory: (String) -> RecorderHealthAPI = { APIClient(token: $0) },
    ensureBinary: @escaping () throws -> URL = { try BinaryManager.ensureBinary() },
    requestPermissions: @escaping () async -> Void = RecorderController.requestSystemPermissions,
    pollInterval: Duration = .seconds(5),
    sourcesStore: RecordingSourcesStore = RecordingSourcesStore(),
    sourceCatalog: RecordingSourceCatalog = ScreenpipeCLICatalog()
) {
    let token = RecorderProcess.newToken()
    self.process = processFactory(token)
    self.api = apiFactory(token)
    self.ensureBinaryClosure = ensureBinary
    self.requestPermissionsClosure = requestPermissions
    self.pollInterval = pollInterval
    self.sourcesStore = sourcesStore
    self.sourceCatalog = sourceCatalog
    AppDelegate.sharedRecorder = self
}
```

(c) Arg builder. Add a private method:

```swift
/// Translate the persisted source selection into `screenpipe record` flags.
/// Monitor IDs are re-validated against the live display list; if none survive,
/// fall back to "all monitors" (no flag). The (slow) display enumeration runs
/// only when an explicit monitor selection exists.
private func buildSourceArguments() async -> (args: [String], monitorIDs: [Int]?, audioNames: [String]?, audioDisabled: Bool) {
    var args: [String] = []
    var resolvedMonitorIDs: [Int]? = nil

    if let wanted = sourcesStore.selectedMonitorIDs, !wanted.isEmpty {
        let live = (try? await sourceCatalog.availableMonitors())?.map(\.id)
        let surviving: [Int]
        if let live { surviving = wanted.filter(live.contains) } else { surviving = wanted }  // catalog failed → trust the stored list
        if !surviving.isEmpty {
            resolvedMonitorIDs = surviving
            for id in surviving { args += ["--monitor-id", String(id)] }
        }
    }

    let audioNames = sourcesStore.selectedAudioDeviceNames
    var audioDisabled = false
    if let audioNames {
        if audioNames.isEmpty { args.append("--disable-audio"); audioDisabled = true }
        else { for name in audioNames { args += ["--audio-device", name] } }
    }

    return (args, resolvedMonitorIDs, audioNames, audioDisabled)
}

private func applyRunningState(_ s: (args: [String], monitorIDs: [Int]?, audioNames: [String]?, audioDisabled: Bool)) {
    runningMonitorIDs = s.monitorIDs
    runningAudioDeviceNames = s.audioNames
    runningAudioDisabled = s.audioDisabled
}
```

(d) Use it everywhere the process is spawned. In `spawnAndPoll(binaryURL:)`:

```swift
private func spawnAndPoll(binaryURL: URL) async {
    let sources = await buildSourceArguments()
    do { try process.start(binaryURL: binaryURL, extraArguments: sources.args) }
    catch {
        status = .error("failed to start recorder: \(error)")
        return
    }
    applyRunningState(sources)
    status = .starting
    startHealthPolling()
}
```

In `resumeScreen()` replace the `try process.start(binaryURL: binaryURL)` block with the same pattern:

```swift
func resumeScreen() async {
    screenPaused = false
    let wasAudioPaused = audioPaused
    do {
        let binaryURL = try ensureBinaryClosure()
        let sources = await buildSourceArguments()
        try process.start(binaryURL: binaryURL, extraArguments: sources.args)
        applyRunningState(sources)
        status = .starting
        startHealthPolling()
        if wasAudioPaused {
            try? await Task.sleep(for: .seconds(8))
            await pauseAudio()
        }
    } catch { status = .error("resume screen failed: \(error)") }
}
```

(`restartAfterCrash()` already routes through `spawnAndPoll`, so it picks up the new args automatically.)

(e) The public apply action:

```swift
/// Persisted source selection has changed (the caller already wrote `RecordingSourcesStore`).
/// Restart the recorder so the new `--monitor-id` / `--audio-device` flags take effect.
func applyRecordingSources() async {
    process.stop()
    healthTask?.cancel(); healthTask = nil
    audioPaused = false; screenPaused = false
    do {
        let binaryURL = try ensureBinaryClosure()
        await spawnAndPoll(binaryURL: binaryURL)
    } catch { status = .error("applying recording sources failed: \(error)") }
}
```

- [ ] **Step 4: Production wiring (`MengoDesktopApp.swift`).** `RecorderController()` already gets the real `RecordingSourcesStore()` / `ScreenpipeCLICatalog()` via the new defaults — **no change needed**. (Leave this step as a checkbox so the executor confirms the app still constructs `RecorderController()` with no args and builds.)

- [ ] **Step 5: Run, verify pass.** Run: `swift test --filter MengoDesktopTests`
Expected: PASS — the new arg-building / apply tests plus all pre-existing ones.

- [ ] **Step 6: Commit.**

```bash
git add Sources/MengoDesktop/RecorderController.swift Tests/MengoDesktopTests/RecorderControllerTests.swift
git commit -m "MengoDesktop: RecorderController builds --monitor-id/--audio-device args from RecordingSourcesStore + applyRecordingSources() (TDD)"
```

---

## Task 7: `RecordingSourcesView` (the sheet) + wire it into the Memory pane

**Files:**
- Create: `Sources/MengoDesktop/RecordingSourcesView.swift`
- Modify: `Sources/MengoDesktop/MemoryPane.swift`

No automated tests (SwiftUI view; covered by the manual checklist in Task 8). Build + relaunch to verify in Task 9.

- [ ] **Step 1: Create `Sources/MengoDesktop/RecordingSourcesView.swift`:**

```swift
import SwiftUI

/// "Recording sources" sheet — pick which displays and microphones screenpipe
/// records. Styled after macOS → Settings → Displays: a row of display thumbnails
/// up top, an audio-device toggle list below, an "Apply & restart" footer.
/// Applying writes `RecordingSourcesStore` and restarts the recorder.
struct RecordingSourcesView: View {
    let recorder: RecorderController
    var store = RecordingSourcesStore()
    var catalog: RecordingSourceCatalog = ScreenpipeCLICatalog()
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var loadError: String?
    @State private var monitors: [MonitorInfo] = []
    @State private var devices: [AudioDeviceInfo] = []
    @State private var selectedMonitorIDs: Set<Int> = []
    @State private var selectedDeviceNames: Set<String> = []
    // The selection that's actually running, captured on load — for the "changed?" check.
    @State private var baselineMonitorIDs: Set<Int> = []
    @State private var baselineDeviceNames: Set<String> = []
    @State private var applying = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if loading { Spacer(); ProgressView("Looking for displays and microphones…").controlSize(.small); Spacer() }
            else if let loadError { Spacer(); errorView(loadError); Spacer() }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        displayStrip
                        Divider().overlay(Theme.separator)
                        audioSection
                    }
                    .padding(20)
                }
            }
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 540, height: 460)
        .background(Theme.windowBackground)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Text("Recording sources").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.paneBackground)
    }

    // MARK: Displays

    private var displayStrip: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 22) {
                    ForEach(monitors) { m in monitorThumb(m) }
                }
                .padding(.horizontal, 4).padding(.vertical, 6)
            }
            Text(displayCaption).font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
    }

    private func monitorThumb(_ m: MonitorInfo) -> some View {
        let on = selectedMonitorIDs.contains(m.id)
        let aspect = max(0.3, Double(m.width) / Double(max(1, m.height)))
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? Theme.accent : Theme.separator, lineWidth: on ? 2 : 1))
                    .frame(width: 116, height: 116 / aspect)
                    .frame(height: 88, alignment: .center)        // keep the row a stable height
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .background(Circle().fill(Theme.windowBackground))
                        .padding(4)
                }
            }
            .opacity(on ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { toggleMonitor(m.id) }
            VStack(spacing: 1) {
                Text(m.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.primaryText)
                Text("\(m.width)×\(m.height)").font(.system(size: 9)).foregroundStyle(Theme.mutedText)
                if m.isDefault { Text("Main").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.mutedText) }
            }
        }
    }

    private func toggleMonitor(_ id: Int) {
        if selectedMonitorIDs.contains(id) {
            guard selectedMonitorIDs.count > 1 else { return }   // always ≥1 display
            selectedMonitorIDs.remove(id)
        } else { selectedMonitorIDs.insert(id) }
    }

    private var displayCaption: String {
        "Recording \(selectedMonitorIDs.count) of \(monitors.count) display\(monitors.count == 1 ? "" : "s")"
    }

    // MARK: Audio

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio sources").font(Theme.headline).foregroundStyle(Theme.primaryText)
            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, d in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.displayName).foregroundStyle(Theme.primaryText)
                            Text(kindLabel(d.kind)).font(Theme.caption).foregroundStyle(Theme.mutedText)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { selectedDeviceNames.contains(d.name) },
                            set: { on in if on { selectedDeviceNames.insert(d.name) } else { selectedDeviceNames.remove(d.name) } }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    if idx < devices.count - 1 { Divider().overlay(Theme.separator) }
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
            if selectedDeviceNames.isEmpty {
                Text("No audio sources — microphone capture will be off.")
                    .font(Theme.caption).foregroundStyle(Theme.paused)
            }
        }
    }

    private func kindLabel(_ k: AudioDeviceInfo.Kind) -> String {
        switch k { case .input: return "input"; case .output: return "output"; case .unknown: return "audio" }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Changes restart recording.").font(Theme.caption).foregroundStyle(Theme.mutedText)
            Spacer()
            Button("Cancel") { dismiss() }
            Button {
                Task { await apply() }
            } label: {
                if applying { ProgressView().controlSize(.small) } else { Text("Apply & restart recording") }
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .disabled(!canApply || applying)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.paneBackground)
    }

    private var canApply: Bool {
        !loading && loadError == nil && !selectedMonitorIDs.isEmpty
            && (selectedMonitorIDs != baselineMonitorIDs || selectedDeviceNames != baselineDeviceNames)
    }

    // MARK: Load / apply

    private func load() async {
        do {
            async let m = catalog.availableMonitors()
            async let d = catalog.availableAudioDevices()
            let (mons, devs) = try await (m, d)
            monitors = mons; devices = devs

            // Seed the selection from what's actually running, else from screenpipe's defaults.
            let runningMonitorNames = Set(recorder.lastHealth?.monitors ?? [])
            if let ids = recorder.runningMonitorIDs { selectedMonitorIDs = Set(ids) }
            else if !runningMonitorNames.isEmpty {
                // /health gives names like "Display 1 (1728x1117)" — match by leading name.
                selectedMonitorIDs = Set(mons.filter { m in runningMonitorNames.contains { $0.hasPrefix(m.name) } }.map(\.id))
            }
            if selectedMonitorIDs.isEmpty { selectedMonitorIDs = Set(mons.map(\.id)) }   // default = all

            if let names = recorder.runningAudioDeviceNames { selectedDeviceNames = Set(names) }
            else if recorder.runningAudioDisabled { selectedDeviceNames = [] }
            else if let live = recorder.lastHealth?.audioPipeline?.audioDevices, !live.isEmpty {
                selectedDeviceNames = Set(devs.filter { live.contains($0.name) }.map(\.name))
            } else {
                // recorder down / unknown → screenpipe's default: default input + system-audio output
                selectedDeviceNames = Set(devs.filter { $0.kind == .output || ($0.kind == .input && $0.isDefault) }.map(\.name))
            }

            baselineMonitorIDs = selectedMonitorIDs
            baselineDeviceNames = selectedDeviceNames
            loading = false
        } catch {
            loadError = "Couldn’t list displays/microphones (\(error.localizedDescription))."
            loading = false
        }
    }

    private func apply() async {
        applying = true
        // "all monitors selected" → store nil (so a newly-plugged display is auto-included next launch).
        store.selectedMonitorIDs = (selectedMonitorIDs.count == monitors.count) ? nil : selectedMonitorIDs.sorted()
        // audio: none → [] (disable); a set that equals screenpipe's default set → nil; else the explicit names.
        let defaultAudioSet = Set(devices.filter { $0.kind == .output || ($0.kind == .input && $0.isDefault) }.map(\.name))
        if selectedDeviceNames.isEmpty { store.selectedAudioDeviceNames = [] }
        else if selectedDeviceNames == defaultAudioSet { store.selectedAudioDeviceNames = nil }
        else { store.selectedAudioDeviceNames = selectedDeviceNames.sorted() }
        await recorder.applyRecordingSources()
        applying = false
        dismiss()
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.paused)
            Text(msg).font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }.padding(40)
    }
}
```

> Note: `RecordingSourcesView` constructs its own `RecordingSourcesStore()` and `ScreenpipeCLICatalog()` by default — both are cheap value types pointing at `UserDefaults.standard` / the bundled binary. The `RecorderController` it's handed already shares the same `UserDefaults`, so writes here are visible to `applyRecordingSources()`.

- [ ] **Step 2: Wire the button + sheet into `MemoryPane.swift`.** Add a `@State private var showSources = false` near `@State private var appeared`. In `controls`, add the "Configure sources…" button after "Reveal recordings" (both plain/orange now from Task 2):

```swift
Spacer(minLength: 12)
Button { NSWorkspace.shared.open(recorder.dataFolderURL) } label: {
    Label("Reveal recordings", systemImage: "folder")
}
.buttonStyle(.plain).foregroundStyle(Theme.accent)
Button { showSources = true } label: {
    Label("Configure sources…", systemImage: "slider.horizontal.3")
}
.buttonStyle(.plain).foregroundStyle(Theme.accent)
```

And attach the sheet to the outer `ScrollView` in `body` (next to `.background(...)`):

```swift
.sheet(isPresented: $showSources) { RecordingSourcesView(recorder: recorder) }
```

- [ ] **Step 3: When source-config has audio disabled, swap the Pause-audio button for a note.** In `controls`, wrap the audio button:

```swift
if recorder.runningAudioDisabled {
    Label("Microphone off — no audio sources selected", systemImage: "mic.slash")
        .font(Theme.caption).foregroundStyle(Theme.mutedText).labelStyle(.titleAndIcon)
} else {
    Button { Task { await audioAction() } } label: {
        Label(audioTitle, systemImage: audioPausedNow ? "mic" : "mic.slash")
    }
    .buttonStyle(.bordered).disabled(disableControls)
}
```

- [ ] **Step 4: Build.** Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit.**

```bash
git add Sources/MengoDesktop/RecordingSourcesView.swift Sources/MengoDesktop/MemoryPane.swift
git commit -m "MengoDesktop: Recording sources sheet (display thumbnails + mic toggles, Apply & restart) wired into the Memory pane"
```

---

## Task 8: Memory-pane stat tiles reflect the recording configuration

**Files:**
- Modify: `Sources/MengoDesktop/MemoryPane.swift`

- [ ] **Step 1: Re-point the "displays" / "mic sources" counts.** In `MemoryPane.swift` replace `displayCount` / `micCount`:

```swift
private var displayCount: Int? {
    recorder.runningMonitorIDs?.count ?? recorder.lastHealth?.monitors?.count
}
private var micCount: Int? {
    if recorder.runningAudioDisabled { return 0 }
    if let names = recorder.runningAudioDeviceNames { return names.count }
    return recorder.lastHealth?.audioPipeline?.audioDevices?.filter { $0.lowercased().contains("input") }.count
}
```

- [ ] **Step 2: Build.** Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit.**

```bash
git add Sources/MengoDesktop/MemoryPane.swift
git commit -m "MengoDesktop: Memory pane — 'displays'/'mic sources' tiles count the active recording config"
```

---

## Task 9: Update the manual smoke checklist; full test run; rebuild + relaunch + eyeball

**Files:**
- Modify: `docs/manual-smoke-tests/mengo-phase-2-memory.md`

- [ ] **Step 1: Add a "Recording sources" section + polish checks** to `docs/manual-smoke-tests/mengo-phase-2-memory.md` (append under the existing "App behaviour" content):

```markdown
### Recording sources (Memory pane)
- Click **Configure sources…** → a sheet opens; a brief spinner, then a row of display thumbnails and an audio-device list.
- The displays / mics that are *currently being recorded* are pre-selected (orange ring on displays, toggle on for audio).
- Deselect one display, click **Apply & restart recording**. The pane shows "Starting…" then "Recording"; `curl -s localhost:3030/health | python3 -c 'import json,sys; print(json.load(sys.stdin)["monitors"])'` shows only the kept display(s). The "displays" stat tile updates to match.
- Open the sheet again, turn **off all audio toggles**, Apply. Recording resumes video-only: the pane shows "Microphone off — no audio sources selected" instead of the Pause-audio button; `/health` audio devices are empty / `audio_status` reflects no audio; the "mic sources" tile reads 0.
- Re-enable audio + all displays, Apply → back to the original behaviour.
- Try to deselect the *last* remaining display — it refuses (stays selected).
- Quit the app, unplug an external display, relaunch → no crash; the pane reads "Recording" with the built-in display only (the stored selection that referenced the unplugged display fell back to "all").

### Polish
- The **Pause screen** button has an icon (not a blank gap), matching the menu-bar "Pause screen" item.
- There is **no "View log"** link on the Memory pane (it's still in the menu-bar dropdown).
- The four "This session" tiles are the **same height**.
- The selected sidebar row and the in-pane links ("Reveal recordings", "Configure sources…") are **brand orange**, not blue.
```

- [ ] **Step 2: Full test run.** Run: `swift test`
Expected: all suites PASS (existing 73 + the new SourceCatalog/Store/Controller tests).

- [ ] **Step 3: Rebuild + re-sign the app.** Run: `./build-mengo.sh`
Expected: it assembles `./MengoDesktop.app`, copies the helper + logo, generates the `.icns`, codesigns — ends without error. (If the screenpipe-helper download step is flaky, re-run; it's network-dependent.)

- [ ] **Step 4: Relaunch + eyeball.** Quit any running MengoDesktop, then `open ./MengoDesktop.app`. Walk the "Recording sources" + "Polish" checklist items from Step 1. If the Pause-screen `rectangle.slash` glyph looks wrong, switch to `eye.slash` / `eye` in `MemoryPane.swift` + `MenuBarContent.swift`, rebuild, re-check, and amend the relevant commit (or add a small follow-up commit).

- [ ] **Step 5: Commit the checklist + any glyph tweak.**

```bash
git add docs/manual-smoke-tests/mengo-phase-2-memory.md
git commit -m "MengoDesktop: smoke checklist — recording-sources picker + polish checks"
```

---

## Self-review notes (filled by the plan author)

- **Spec coverage:** Part A (catalog → Task 3; store → Task 4; controller args + `applyRecordingSources` → Tasks 5–6; sheet → Task 7; tiles reflect config → Task 8) and Part B polish (icon/View-log/tiles/degraded copy → Task 1; blue→orange → Task 2). Manual checklist → Task 9. ✅ all spec sections map to a task.
- **Placeholder scan:** no "TBD"/"handle errors"/"similar to Task N" — every code step shows the code. The one deliberately-deferred detail (the exact Pause-screen SF Symbol) has a concrete default *and* a concrete fallback, decided at Task 1 / re-checked at Task 9. ✅
- **Type consistency:** `RecordingSourceCatalog` (protocol) / `ScreenpipeCLICatalog` (impl) / `SourceCatalog` (pure decoders) used consistently; `MonitorInfo`/`AudioDeviceInfo` field names match between Task 3 and Tasks 6–7; `RecorderProcessControlling.start(binaryURL:extraArguments:)` matches between Task 5 and Task 6; `RecorderController` new members (`runningMonitorIDs`, `runningAudioDeviceNames`, `runningAudioDisabled`, `applyRecordingSources()`) referenced identically in Tasks 6–8 and the tests. ✅
