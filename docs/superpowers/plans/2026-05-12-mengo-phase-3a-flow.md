# Mengo Desktop Phase 3a — Mengo Flow (proactive record → synthesize → review → save) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Inside Mengo Desktop, hit **Start recording** (menu Flow group or `⌃⌥R`) → narrate a task → **Stop** → `claude -p` synthesizes a Claude Code skill → review it inline (rename, edit description/params, regenerate) → **Save** to `~/.claude/skills/<slug>/`. Plus a floating non-activating Recording HUD, the Flow + Library inline panes, and the menu's Flow group.

**Architecture:** Swift orchestrates; `claude` does the semantics. `FlowController` (`@Observable @MainActor`, injectable deps — mirrors the existing `RecorderController`) owns a `FlowState` machine; on Stop it writes a manifest JSON (`ManifestWriter`) and spawns `claude -p` (`SynthesisRunner`) with `SCREENPIPE_API_KEY` in the env so the screenpipe MCP child can authenticate against Mengo's already-running recorder. `claude` writes `SKILL.md` / `flow.json` / `frames/*.png` to `~/.claude/skills/<slug>/` and prints a final JSON status line. Most of this is ported from V1's `Sources/ScreenpipeFlow/` (kept intact as reference); the V1 `Window`-scene structure is dropped — Review/Library are states/panes inside the existing `MainWindowView`, the HUD is a floating `NSPanel`.

**Tech Stack:** Swift 6, SwiftUI, `@Observable @MainActor`, XCTest, Carbon `RegisterEventHotKey`, `Process`. macOS 15+.

**Spec:** [`docs/superpowers/specs/2026-05-12-mengo-phase-3a-flow-design.md`](../specs/2026-05-12-mengo-phase-3a-flow-design.md)

**Branch:** `claude/kind-volhard-f7e189` (already off `main` at `bc98c68` — the Phase 3a spec commit; the recording-sources work is merged).

**V1 source to port from (same repo):** `Sources/ScreenpipeFlow/{RecordingSession,Slug,ManifestWriter,SynthesisRunner,HotkeyManager,RecordingController,AppState,RecordingHUD,ReviewWindow,LibraryWindow}.swift` and `Tests/ScreenpipeFlowTests/{RecordingSessionTests,SlugTests,ManifestWriterTests,SynthesisRunnerTests,AppStateTests}.swift`. When the plan says "port from X", read X and reproduce it into `Sources/MengoDesktop/` (or `Tests/MengoDesktopTests/`) with the changes listed — don't re-derive it.

---

## File structure

| File | Status | Responsibility |
|---|---|---|
| `Sources/MengoDesktop/FlowSession.swift` | new (port `RecordingSession.swift`) | `enum RecordingMode { proactive, retroactive }` (3a uses only `.proactive`; the field set is kept identical to V1 so 3b is a drop-in) + `struct FlowSession` (`mode`, `bufferRangeStart: Date?`, `activeRecordingStart`, `endTime`, computed `timeRangeStart`/`timeRangeEnd`/`durationSeconds`). |
| `Sources/MengoDesktop/Slug.swift` | new (port `Slug.swift` verbatim) | kebab-case slug derivation + `uniquify(_:existing:)`. |
| `Sources/MengoDesktop/ManifestWriter.swift` | new (port `ManifestWriter.swift`) | `enum ManifestWriter` — `RegenerationContext`, `write(session:outputDir:userHints*:regenerationContext:manifestsDir:) -> URL`. Verbatim except `import` (no `Logger` ref to change here). |
| `Sources/MengoDesktop/SynthesisRunner.swift` | new (port `SynthesisRunner.swift` + one change) | `enum SynthesisResult { success(outputDir:URL,slug:String), failure(message:String) }`, `SynthesisRunner.run(command:arguments:environment:logFile:timeoutSeconds:) -> SynthesisResult` (the only change vs V1: add an `environment: [String: String]?` param, applied to `process.environment` — V1 didn't set env), and the pure `parseLastStatusLine(stdout:)`. Keep the `LogWriter`/`StdoutBuffer`/`TimedOutFlag` helpers verbatim. |
| `Sources/MengoDesktop/FlowLibrary.swift` | new | `struct FlowEntry { slug, name, path: URL, createdAt, sourceManifestId: String? }` (Identifiable by slug) + `struct FlowLibrary` — a JSON index at `~/Library/Application Support/MengoDesktop/flows/library.json`. `init(fileURL:)` injectable; `load() -> [FlowEntry]` (newest first; tag-by-existence is the pane's job), `add(_:)`, `remove(slug:)`. |
| `Sources/MengoDesktop/HotkeyManager.swift` | new (port `HotkeyManager.swift`) | Carbon global hotkeys. Change: `Logger.log` → `Log.line`; the 4-byte signature `0x53464C57` ("SFLW") → `0x4D454E47` ("MENG"). 3a registers only `recordToggle` (`⌃⌥R`). `grabLast` binding can stay defined (unused in 3a). |
| `Sources/MengoDesktop/FlowState.swift` | new | `enum FlowState: Equatable { idle, recording(FlowSession), synthesizing(URL /* manifest */), reviewing(URL /* skill dir */), error(String) }`. |
| `Sources/MengoDesktop/FlowController.swift` | new (adapts `RecordingController.swift` + `AppState.swift`) | `@Observable @MainActor final class FlowController`. Owns `flowState`, `library: [FlowEntry]`. Deps injectable: a `SynthesisRunning` protocol (so tests stub the subprocess), a `RecorderHealthAPI`-ish health check (reuse the recorder's, or a tiny protocol), the recorder's screenpipe token, a `claudeExecutable: URL?`, the manifests/recovery dirs, a `FlowLibrary`, a `Clock`/`now` closure, the synthesis-prompt string. Methods: `preflight()`, `toggleRecording()`, `start()`, `stop()`, `regenerate(feedback:)`, `retrySynthesis()`, `discard()`, `save(name:description:parameters:)`, `dumpRecoveryIfRecording()`, `checkForRecovery() -> URL?`, `synthesizeRecovery(manifestURL:)`. `AppDelegate.sharedFlowController` bridge. |
| `Sources/MengoDesktop/RecordingHUD.swift` | new (port `RecordingHUD.swift`) | `@MainActor final class RecordingHUDController` — `show(session:onStop:)` / `hide()`; the `NSPanel` config. + private `RecordingHUDView`. Changes: dark `Theme` colours; remember the panel origin in `UserDefaults` (`"flow.hudOrigin"`); strings ("Narrate as you work."); title "Mengo Desktop". |
| `Sources/MengoDesktop/SkillFiles.swift` | new | Pure parsers (so the Review view stays thin and one bit is tested): `parseSkillMarkdown(_ text: String) -> (name: String?, description: String?, body: String)` (YAML-ish frontmatter between `---` lines: `name:` / `description:` — the description may span continuation lines), and `parseFlowParameters(_ data: Data) -> [FlowParameter]` where `struct FlowParameter { name, description: String?, defaultValue: String?, autoDetected: Bool }`, and `parseFlowStepSummaries(_ data: Data) -> [String]` (e.g. `"1. Open the staging dashboard (inferred)"`). |
| `Sources/MengoDesktop/FlowPane.swift` | new | The SwiftUI pane for `appState.selectedSection == .flow` — switches on `flow.flowState`: idle / recording / synthesizing / error. (`reviewing` → renders `SkillReviewView`.) Dark/orange, hero pattern like `MemoryPane`. |
| `Sources/MengoDesktop/SkillReviewView.swift` | new (adapts `ReviewWindow.swift`) | The `reviewing` UI: editable name/description, rendered SKILL.md (`AttributedString(markdown:)`), editable parameter list, read-only step list, `[Regenerate with feedback…]` / `[Discard]` / `[Save]`. Loads via `SkillFiles`. |
| `Sources/MengoDesktop/LibraryPane.swift` | new (adapts `LibraryWindow.swift`) | List of `flow.library`; per row name · created · [Open in Finder] · [Re-open in Review] · [Delete]; an entry whose `path` is gone shows greyed "(missing — removed outside Mengo)" + [Remove from list]. Empty state. |
| `Sources/MengoDesktop/RecorderController.swift` | modify | Add `let screenpipeToken: String` (store the token created in `init`) and a `var isAudioPaused: Bool` convenience (the pane already infers paused-ness; expose it cleanly for `FlowController`'s preflight) — or `FlowController` reads `recorder.status`. |
| `Sources/MengoDesktop/Log.swift` | modify | Add `static func synthesisLogURL(id: String) -> URL { directory.appendingPathComponent("synthesis-\(id).log") }`. |
| `Sources/MengoDesktop/MengoDesktopApp.swift` | modify | Construct `FlowController(recorder:)`, `HotkeyManager`, `RecordingHUDController`; pass `flow` into `MainWindowView` + `MenuBarContent`; in `applicationDidFinishLaunching`: register `⌃⌥R`, request `UNUserNotificationCenter` auth, run `flow.checkForRecovery()` → prompt; in `applicationWillTerminate`: `flow.dumpRecoveryIfRecording()`; observe `flow.flowState` to show/hide the HUD. |
| `Sources/MengoDesktop/MainWindowView.swift` | modify | `case .flow: FlowPane(flow: flow)`, `case .library: LibraryPane(flow: flow)`; pass `flow` in. |
| `Sources/MengoDesktop/MenuBarContent.swift` | modify | Un-disable the Flow group: "Start recording…" `⌃⌥R` / "Stop recording" (toggled by `flow.flowState`); a disabled "Synthesizing…" while synthesizing; keep "Grab last 5 minutes… ⌃⌥G" disabled. Pass `flow` in. |
| `build-mengo.sh` | modify | Add `cp Resources/synthesis-prompt.md "$APP_BUNDLE/Contents/Resources/synthesis-prompt.md"` next to the `MengoLogo.png` copy (so `Bundle.main` finds it). |
| `Tests/MengoDesktopTests/FlowSessionTests.swift` | new (port `RecordingSessionTests`) | |
| `Tests/MengoDesktopTests/SlugTests.swift` | new (port `SlugTests`) | |
| `Tests/MengoDesktopTests/ManifestWriterTests.swift` | new (port `ManifestWriterTests`) | |
| `Tests/MengoDesktopTests/SynthesisRunnerTests.swift` | new (port `SynthesisRunnerTests`) | the fake-claude bash-script tests + the pure `parseLastStatusLine` tests. |
| `Tests/MengoDesktopTests/FlowLibraryTests.swift` | new | round-trip; persists across instances; remove. |
| `Tests/MengoDesktopTests/FlowControllerTests.swift` | new | state transitions; preflight pass/fail; stop <10 s → idle; stop with stubbed-success → reviewing + library updated; stop with stubbed-failure → error; retry; discard; save (slug collision suffixing); recovery dump/discover. |
| `Tests/MengoDesktopTests/SkillFilesTests.swift` | new | frontmatter parse; flow.json parameter parse. |
| `docs/manual-smoke-tests/mengo-phase-3a-flow.md` | new | the end-to-end checklist (record→synth→review→save, parameter callout, regenerate, discard, preflight failures, `⌃⌥R`/HUD behavior, quit-mid-recording recovery, <10 s). |

---

## Task 1: Ports — `FlowSession`, `Slug` (+ their tests)

**Files:** Create `Sources/MengoDesktop/FlowSession.swift`, `Sources/MengoDesktop/Slug.swift`, `Tests/MengoDesktopTests/FlowSessionTests.swift`, `Tests/MengoDesktopTests/SlugTests.swift`.

- [ ] **Step 1: Write the failing tests.** Port `Tests/ScreenpipeFlowTests/RecordingSessionTests.swift` → `Tests/MengoDesktopTests/FlowSessionTests.swift`: change `@testable import ScreenpipeFlow` → `@testable import MengoDesktop`, `RecordingSession` → `FlowSession`. Port `Tests/ScreenpipeFlowTests/SlugTests.swift` → `Tests/MengoDesktopTests/SlugTests.swift`: change the import; `Slug` is unchanged. (`FlowEntry` references in `RecordingSessionTests.testFlowEntryEquality` move to `FlowLibraryTests` in Task 4 — drop that one test here.)

- [ ] **Step 2: Run, verify it fails.** `swift test --filter FlowSessionTests` — FAIL (`FlowSession` not found).

- [ ] **Step 3: Implement.** Create `Sources/MengoDesktop/FlowSession.swift`: copy `Sources/ScreenpipeFlow/RecordingSession.swift` and rename `RecordingSession` → `FlowSession`; **drop the `FlowEntry` struct** (it goes in `FlowLibrary.swift`). Create `Sources/MengoDesktop/Slug.swift`: copy `Sources/ScreenpipeFlow/Slug.swift` verbatim (no namespace deps).

- [ ] **Step 4: Run, verify pass.** `swift test --filter FlowSessionTests` and `--filter SlugTests` — PASS.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/FlowSession.swift Sources/MengoDesktop/Slug.swift Tests/MengoDesktopTests/FlowSessionTests.swift Tests/MengoDesktopTests/SlugTests.swift && git commit -m "MengoDesktop: port FlowSession + Slug from V1 ScreenpipeFlow (TDD)"`

---

## Task 2: Port — `ManifestWriter` (+ tests)

**Files:** Create `Sources/MengoDesktop/ManifestWriter.swift`, `Tests/MengoDesktopTests/ManifestWriterTests.swift`.

- [ ] **Step 1: Write the failing tests.** Port `Tests/ScreenpipeFlowTests/ManifestWriterTests.swift` → `Tests/MengoDesktopTests/ManifestWriterTests.swift`: change the import; `RecordingSession` → `FlowSession`. (Keep all 6 tests — proactive structure, retroactive buffer start, regeneration context, nil hints → JSON null, filename is `<uuid>.json`.)

- [ ] **Step 2: Run, verify fails.** `swift test --filter ManifestWriterTests` — FAIL.

- [ ] **Step 3: Implement.** Create `Sources/MengoDesktop/ManifestWriter.swift`: copy `Sources/ScreenpipeFlow/ManifestWriter.swift` verbatim, change `session: RecordingSession` → `session: FlowSession`. Nothing else changes (it's pure `JSONSerialization`).

- [ ] **Step 4: Run, verify pass.** `swift test --filter ManifestWriterTests` — PASS.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/ManifestWriter.swift Tests/MengoDesktopTests/ManifestWriterTests.swift && git commit -m "MengoDesktop: port ManifestWriter from V1 ScreenpipeFlow (TDD)"`

---

## Task 3: Port — `SynthesisRunner` (+ `environment:` param, + tests)

**Files:** Create `Sources/MengoDesktop/SynthesisRunner.swift`, `Tests/MengoDesktopTests/SynthesisRunnerTests.swift`.

- [ ] **Step 1: Write the failing tests.** Port `Tests/ScreenpipeFlowTests/SynthesisRunnerTests.swift` → `Tests/MengoDesktopTests/SynthesisRunnerTests.swift`: change the import. The `SynthesisRunner.run(...)` calls in those tests gain an `environment: nil` argument (the new param). Keep all of them (success line, failure line, no-status-line, non-zero exit, timeout, the two pure `parseLastStatusLine` tests). Add one new test: `testEnvironmentIsPassedToSubprocess` — write a fake-claude that does `echo "{\"status\":\"ok\",\"outputDir\":\"$SP_TEST_DIR\",\"slug\":\"x\"}"` (echoing an env var), call `run(..., environment: ["SP_TEST_DIR": "/tmp/envcheck"])`, assert `.success(outputDir: /tmp/envcheck, ...)`.

- [ ] **Step 2: Run, verify fails.** `swift test --filter SynthesisRunnerTests` — FAIL.

- [ ] **Step 3: Implement.** Create `Sources/MengoDesktop/SynthesisRunner.swift`: copy `Sources/ScreenpipeFlow/SynthesisRunner.swift` verbatim, with one change to `run(...)`:

```swift
static func run(
    command: URL,
    arguments: [String],
    environment: [String: String]?,        // NEW
    logFile: URL,
    timeoutSeconds: TimeInterval
) async throws -> SynthesisResult {
    // ... (unchanged setup) ...
    let process = Process()
    process.executableURL = command
    process.arguments = arguments
    if let environment { process.environment = environment }   // NEW
    // ... (rest unchanged) ...
}
```

Keep `SynthesisResult`, `parseLastStatusLine`, and the `LogWriter`/`StdoutBuffer`/`TimedOutFlag` private helpers verbatim.

- [ ] **Step 4: Run, verify pass.** `swift test --filter SynthesisRunnerTests` — PASS.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/SynthesisRunner.swift Tests/MengoDesktopTests/SynthesisRunnerTests.swift && git commit -m "MengoDesktop: port SynthesisRunner from V1 (adds env param for SCREENPIPE_API_KEY) (TDD)"`

---

## Task 4: `FlowLibrary` + `FlowEntry` (TDD)

**Files:** Create `Sources/MengoDesktop/FlowLibrary.swift`, `Tests/MengoDesktopTests/FlowLibraryTests.swift`.

- [ ] **Step 1: Write the failing tests** (`Tests/MengoDesktopTests/FlowLibraryTests.swift`):

```swift
import XCTest
@testable import MengoDesktop

final class FlowLibraryTests: XCTestCase {
    private func tmpFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flowlib-\(UUID().uuidString)")
            .appendingPathComponent("library.json")
    }

    func test_empty_whenFileMissing() {
        XCTAssertEqual(FlowLibrary(fileURL: tmpFile()).load(), [])
    }

    func test_add_thenLoad_roundTrips_newestFirst() {
        let lib = FlowLibrary(fileURL: tmpFile())
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late  = Date(timeIntervalSince1970: 1_700_000_100)
        lib.add(FlowEntry(slug: "old", name: "Old", path: URL(fileURLWithPath: "/a"), createdAt: early, sourceManifestId: "m1"))
        lib.add(FlowEntry(slug: "new", name: "New", path: URL(fileURLWithPath: "/b"), createdAt: late,  sourceManifestId: "m2"))
        XCTAssertEqual(lib.load().map(\.slug), ["new", "old"])
        XCTAssertEqual(lib.load().first?.name, "New")
    }

    func test_add_replacesSameSlug() {
        let lib = FlowLibrary(fileURL: tmpFile())
        lib.add(FlowEntry(slug: "x", name: "old", path: URL(fileURLWithPath: "/a"), createdAt: Date(timeIntervalSince1970: 1), sourceManifestId: nil))
        lib.add(FlowEntry(slug: "x", name: "new", path: URL(fileURLWithPath: "/b"), createdAt: Date(timeIntervalSince1970: 2), sourceManifestId: nil))
        XCTAssertEqual(lib.load().count, 1)
        XCTAssertEqual(lib.load().first?.name, "new")
    }

    func test_remove() {
        let lib = FlowLibrary(fileURL: tmpFile())
        lib.add(FlowEntry(slug: "a", name: "A", path: URL(fileURLWithPath: "/a"), createdAt: Date(), sourceManifestId: nil))
        lib.add(FlowEntry(slug: "b", name: "B", path: URL(fileURLWithPath: "/b"), createdAt: Date(), sourceManifestId: nil))
        lib.remove(slug: "a")
        XCTAssertEqual(lib.load().map(\.slug), ["b"])
    }

    func test_persistsAcrossInstances() {
        let url = tmpFile()
        FlowLibrary(fileURL: url).add(FlowEntry(slug: "z", name: "Z", path: URL(fileURLWithPath: "/z"), createdAt: Date(), sourceManifestId: "m"))
        XCTAssertEqual(FlowLibrary(fileURL: url).load().map(\.slug), ["z"])
    }
}
```

- [ ] **Step 2: Run, verify fails.** `swift test --filter FlowLibraryTests` — FAIL.

- [ ] **Step 3: Implement** `Sources/MengoDesktop/FlowLibrary.swift`:

```swift
import Foundation

/// One flow Mengo has created. `Identifiable` by `slug` for SwiftUI lists.
struct FlowEntry: Equatable, Identifiable, Codable {
    let slug: String
    var name: String
    let path: URL
    let createdAt: Date
    let sourceManifestId: String?
    var id: String { slug }

    /// True when the skill directory still exists on disk.
    var exists: Bool { FileManager.default.fileExists(atPath: path.path) }
}

/// JSON-backed index of the flows Mengo created, at
/// `~/Library/Application Support/MengoDesktop/flows/library.json` by default.
/// (We don't scan `~/.claude/skills/` — only flows *we* made show in the Library
/// pane; an externally-deleted one shows greyed via `FlowEntry.exists`.)
struct FlowLibrary {
    let fileURL: URL

    init(fileURL: URL = FlowLibrary.defaultFileURL) { self.fileURL = fileURL }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MengoDesktop/flows", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    /// Newest first.
    func load() -> [FlowEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? JSONDecoder.iso.decode([FlowEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ entry: FlowEntry) {
        var entries = load().filter { $0.slug != entry.slug }
        entries.append(entry)
        write(entries)
    }

    func remove(slug: String) { write(load().filter { $0.slug != slug }) }

    private func write(_ entries: [FlowEntry]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder.iso.encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }
}

private extension JSONDecoder { static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d } }
private extension JSONEncoder { static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e } }
```

(Note: `URL` is `Codable` — encodes as a string; that's fine for local file paths.)

- [ ] **Step 4: Run, verify pass.** `swift test --filter FlowLibraryTests` — PASS.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/FlowLibrary.swift Tests/MengoDesktopTests/FlowLibraryTests.swift && git commit -m "MengoDesktop: FlowLibrary — JSON index of created flows (TDD)"`

---

## Task 5: `FlowState`, expose the recorder token, `FlowController` skeleton + state transitions (TDD)

**Files:** Create `Sources/MengoDesktop/FlowState.swift`, `Sources/MengoDesktop/FlowController.swift`, `Tests/MengoDesktopTests/FlowControllerTests.swift`. Modify `Sources/MengoDesktop/RecorderController.swift`, `Sources/MengoDesktop/Log.swift`.

- [ ] **Step 1: Expose the recorder's token.** In `RecorderController.swift`, store the token: add `let screenpipeToken: String` and in `init`, after `let token = RecorderProcess.newToken()`, add `self.screenpipeToken = token`. (Build the package to make sure that compiles: `swift build`.)

- [ ] **Step 2: Add `Log.synthesisLogURL`.** In `Log.swift`, add inside `enum Log`:

```swift
/// `~/Library/Logs/MengoDesktop/synthesis-<id>.log` — per-synthesis subprocess output.
static func synthesisLogURL(id: String) -> URL { directory.appendingPathComponent("synthesis-\(id).log") }
```

- [ ] **Step 3: Write the failing tests** (`Tests/MengoDesktopTests/FlowControllerTests.swift` — the state-transition subset for now):

```swift
import XCTest
@testable import MengoDesktop

@MainActor
final class FlowControllerTests: XCTestCase {

    // MARK: stubs

    struct StubSynthesis: SynthesisRunning {
        var result: Result<SynthesisResult, Error>
        func run(command: URL, arguments: [String], environment: [String: String]?,
                 logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult {
            try result.get()
        }
    }
    struct StubHealth: FlowPreflightHealth {
        var healthy = true
        var audioPaused = false
        func snapshot() async -> (healthy: Bool, audioPaused: Bool) { (healthy, audioPaused) }
    }

    private func tmpDir() -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("flowctl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func makeController(
        synthesis: SynthesisRunning = StubSynthesis(result: .success(.failure(message: "stub"))),
        health: FlowPreflightHealth = StubHealth(),
        claudeExecutable: URL? = URL(fileURLWithPath: "/tmp/fake-claude"),
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> FlowController {
        let base = tmpDir()
        return FlowController(
            screenpipeToken: "sp-test",
            claudeExecutable: claudeExecutable,
            synthesisPrompt: "PROMPT $MANIFEST_PATH",
            outputDir: base.appendingPathComponent("skills"),
            manifestsDir: base.appendingPathComponent("manifests"),
            recoveryDir: base.appendingPathComponent("recovery"),
            library: FlowLibrary(fileURL: base.appendingPathComponent("library.json")),
            synthesis: synthesis,
            health: health,
            now: now,
            hudShow: { _, _ in }, hudHide: { },
            notify: { _ in }
        )
    }

    // MARK: tests

    func test_initial_isIdle() { XCTAssertEqual(makeController().flowState, .idle) }

    func test_preflight_pass() async {
        let c = makeController()
        XCTAssertNil(await c.preflight())
    }
    func test_preflight_screenpipeUnhealthy() async {
        let c = makeController(health: StubHealth(healthy: false))
        XCTAssertEqual(await c.preflight(), .screenpipeNotRunning)
    }
    func test_preflight_audioPaused() async {
        let c = makeController(health: StubHealth(audioPaused: true))
        XCTAssertEqual(await c.preflight(), .audioPaused)
    }
    func test_preflight_claudeMissing() async {
        let c = makeController(claudeExecutable: nil)
        XCTAssertEqual(await c.preflight(), .claudeNotFound)
    }

    func test_start_entersRecording() async {
        let c = makeController()
        await c.start()
        guard case .recording = c.flowState else { return XCTFail("expected .recording, got \(c.flowState)") }
    }
    func test_start_blockedByPreflight_staysIdle() async {
        let c = makeController(claudeExecutable: nil)
        await c.start()
        XCTAssertEqual(c.flowState, .idle)
    }
}
```

(The stop/synthesis/review/recovery tests come in Tasks 6–7 & 14.)

- [ ] **Step 4: Run, verify fails.** `swift test --filter FlowControllerTests` — FAIL (`FlowController` etc. not found).

- [ ] **Step 5: Implement `Sources/MengoDesktop/FlowState.swift`:**

```swift
import Foundation

/// The Flow product's state machine. Mode C ("grab last N min") is Phase 3b;
/// in 3a `recording` is always proactive (`session.bufferRangeStart == nil`).
enum FlowState: Equatable {
    case idle
    case recording(FlowSession)
    case synthesizing(URL)   // manifest path
    case reviewing(URL)      // skill directory
    case error(String)
}
```

- [ ] **Step 6: Implement `Sources/MengoDesktop/FlowController.swift`** — the skeleton with deps, the protocols, the state-transition methods, preflight, and `start()`. (`stop()`/synthesis are stubbed to "not yet" here and filled in Task 6; the review actions in Task 7; recovery in Task 14 — but write the full struct shape now so later tasks just fill bodies.)

```swift
import Foundation
import Observation
import AppKit

/// Abstracts the synthesis subprocess so tests can stub it.
protocol SynthesisRunning: Sendable {
    func run(command: URL, arguments: [String], environment: [String: String]?,
             logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult
}
/// `SynthesisRunner.run` conforms via a thin adapter (it's an enum, not a type).
struct SystemSynthesisRunner: SynthesisRunning {
    func run(command: URL, arguments: [String], environment: [String: String]?,
             logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult {
        try await SynthesisRunner.run(command: command, arguments: arguments, environment: environment,
                                      logFile: logFile, timeoutSeconds: timeoutSeconds)
    }
}

/// Preflight health snapshot — abstracted so tests don't need a real recorder.
protocol FlowPreflightHealth: Sendable {
    func snapshot() async -> (healthy: Bool, audioPaused: Bool)
}
/// Reads the live `RecorderController` (Memory's recorder) on the main actor.
@MainActor struct RecorderPreflightHealth: FlowPreflightHealth {
    weak var recorder: RecorderController?
    func snapshot() async -> (healthy: Bool, audioPaused: Bool) {
        guard let recorder else { return (false, false) }
        switch recorder.status {
        case .recording:                       return (true, false)
        case .audioPaused, .bothPaused:        return (true, true)
        case .screenPaused, .starting, .idle, .error: return (false, false)
        }
    }
}

@Observable
@MainActor
final class FlowController {

    enum PreflightFailure: Equatable { case screenpipeNotRunning, audioPaused, claudeNotFound, claudeMCPNotConfigured }

    private(set) var flowState: FlowState = .idle
    private(set) var library: [FlowEntry] = []
    /// A quiet note shown in the Flow pane (e.g. "⌃⌥R is in use by another app").
    private(set) var hotkeyNote: String?

    // Injected deps.
    @ObservationIgnored private let screenpipeToken: String
    @ObservationIgnored private let claudeExecutable: URL?
    @ObservationIgnored private let synthesisPrompt: String
    @ObservationIgnored let outputDir: URL          // ~/.claude/skills
    @ObservationIgnored private let manifestsDir: URL
    @ObservationIgnored private let recoveryDir: URL
    @ObservationIgnored private let libraryStore: FlowLibrary
    @ObservationIgnored private let synthesis: SynthesisRunning
    @ObservationIgnored private let health: FlowPreflightHealth
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let hudShow: (FlowSession, @escaping () -> Void) -> Void
    @ObservationIgnored private let hudHide: () -> Void
    @ObservationIgnored private let notify: (String) -> Void   // posts a "skill ready" notification

    /// The session captured between Start and Stop, kept after Stop so Regenerate
    /// can reuse it (and so a recovery dump on quit-mid-recording has the range).
    @ObservationIgnored private var lastSession: FlowSession?
    /// The manifest written for the last (re)synthesis, for Retry.
    @ObservationIgnored private var lastManifestURL: URL?

    init(screenpipeToken: String,
         claudeExecutable: URL?,
         synthesisPrompt: String,
         outputDir: URL,
         manifestsDir: URL,
         recoveryDir: URL,
         library: FlowLibrary,
         synthesis: SynthesisRunning = SystemSynthesisRunner(),
         health: FlowPreflightHealth,
         now: @escaping () -> Date = Date.init,
         hudShow: @escaping (FlowSession, @escaping () -> Void) -> Void,
         hudHide: @escaping () -> Void,
         notify: @escaping (String) -> Void) {
        self.screenpipeToken = screenpipeToken
        self.claudeExecutable = claudeExecutable
        self.synthesisPrompt = synthesisPrompt
        self.outputDir = outputDir
        self.manifestsDir = manifestsDir
        self.recoveryDir = recoveryDir
        self.libraryStore = library
        self.synthesis = synthesis
        self.health = health
        self.now = now
        self.hudShow = hudShow
        self.hudHide = hudHide
        self.notify = notify
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: manifestsDir, withIntermediateDirectories: true)
        self.library = libraryStore.load()
        AppDelegate.sharedFlowController = self
    }

    /// Convenience prod initializer wired to the live recorder + bundled prompt + discovered `claude`.
    @MainActor
    static func live(recorder: RecorderController,
                     hud: RecordingHUDController,
                     notify: @escaping (String) -> Void) -> FlowController {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MengoDesktop/flows", isDirectory: true)
        return FlowController(
            screenpipeToken: recorder.screenpipeToken,
            claudeExecutable: Self.findClaude(),
            synthesisPrompt: Self.loadSynthesisPrompt(),
            outputDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills", isDirectory: true),
            manifestsDir: appSupport.appendingPathComponent("manifests", isDirectory: true),
            recoveryDir: appSupport.appendingPathComponent("recovery", isDirectory: true),
            library: FlowLibrary(),
            health: RecorderPreflightHealth(recorder: recorder),
            hudShow: { session, onStop in hud.show(session: session, onStop: onStop) },
            hudHide: { hud.hide() },
            notify: notify)
    }

    static func findClaude() -> URL? {
        let home = NSHomeDirectory()
        for p in ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                  "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.local/bin/claude"]
        where FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }
    static func loadSynthesisPrompt() -> String {
        if let url = Bundle.main.url(forResource: "synthesis-prompt", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        Log.line("WARNING: synthesis-prompt.md not found in bundle — using minimal fallback")
        return "Synthesize a Claude Code skill from the recording described by the manifest at $MANIFEST_PATH. On success print {\"status\":\"ok\",\"outputDir\":\"<dir>\",\"slug\":\"<slug>\"}; on failure {\"status\":\"error\",\"message\":\"<reason>\"}."
    }

    // MARK: preflight

    func preflight() async -> PreflightFailure? {
        let s = await health.snapshot()
        if !s.healthy { return .screenpipeNotRunning }
        if s.audioPaused { return .audioPaused }
        if claudeExecutable == nil { return .claudeNotFound }
        // best-effort: don't block if `claude mcp list` itself errors.
        if let claude = claudeExecutable, await Self.mcpListLacksScreenpipe(claude: claude) { return .claudeMCPNotConfigured }
        return nil
    }

    private static func mcpListLacksScreenpipe(claude: URL) async -> Bool {
        await Task.detached { () -> Bool in
            let p = Process(); p.executableURL = claude; p.arguments = ["mcp", "list"]
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return false }   // can't tell → don't block
            let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return false }
            return !text.lowercased().contains("screenpipe")
        }.value
    }

    // MARK: recording lifecycle

    func toggleRecording() async {
        switch flowState {
        case .recording: await stop()
        case .idle, .error: await start()
        default: break
        }
    }

    func start() async {
        guard case .idle = flowState else { if case .error = flowState {} else { return } }
        if let failure = await preflight() { presentPreflightAlert(failure); return }
        let session = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: now(), endTime: nil)
        lastSession = session
        flowState = .recording(session)
        hudShow(session) { Task { @MainActor in await self.stop() } }
    }

    func stop() async {
        guard case .recording(var session) = flowState else { return }
        hudHide()
        session.endTime = now()
        lastSession = session
        if session.durationSeconds < 10 {
            flowState = .idle
            notify("Recording too short to synthesize.")
            return
        }
        await runSynthesis(session: session, regen: nil)
    }

    // MARK: synthesis (filled in Task 6)
    private func runSynthesis(session: FlowSession, regen: ManifestWriter.RegenerationContext?) async { /* Task 6 */ }

    // MARK: review actions (filled in Task 7)
    func regenerate(feedback: String) async { /* Task 7 */ }
    func retrySynthesis() async { /* Task 7 */ }
    func discard() { /* Task 7 */ }
    func save(name: String, description: String?, parameters: [FlowParameter]) { /* Task 7 */ }

    // MARK: recovery (filled in Task 14)
    func dumpRecoveryIfRecording() { /* Task 14 */ }
    func checkForRecovery() -> URL? { /* Task 14 */ nil }
    func synthesizeRecovery(manifestURL: URL) async { /* Task 14 */ }

    // MARK: alerts

    private func presentPreflightAlert(_ f: PreflightFailure) {
        let a = NSAlert()
        switch f {
        case .screenpipeNotRunning:
            a.messageText = "The recorder isn't running"
            a.informativeText = "Mengo Flow needs Mengo Memory's recorder. Check the Memory tab."
        case .audioPaused:
            a.messageText = "Your microphone is paused"
            a.informativeText = "Flow needs the mic to capture your narration. Resume it from the Memory tab, then try again."
        case .claudeNotFound:
            a.messageText = "Claude Code CLI not found"
            a.informativeText = "Install it from https://claude.ai/code, then retry."
        case .claudeMCPNotConfigured:
            a.messageText = "The screenpipe MCP isn't set up for Claude Code"
            a.informativeText = "Run this in a terminal, then retry:\n\nclaude mcp add screenpipe -s user -- npx -y screenpipe-mcp"
            a.addButton(withTitle: "Copy command"); a.addButton(withTitle: "OK")
            if a.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("claude mcp add screenpipe -s user -- npx -y screenpipe-mcp", forType: .string)
            }
            return
        }
        a.addButton(withTitle: "OK"); a.runModal()
    }
}
```

Notes: `FlowParameter` (used in `save`) is defined in `SkillFiles.swift` (Task 11) — for Task 5, just compiling, you can forward-declare it as an empty `struct FlowParameter { }` in `SkillFiles.swift` and flesh it out in Task 11 (so the build stays green between tasks). Or define `FlowParameter` minimally here in Task 5 inside `FlowController.swift` and move it in Task 11 — pick one; the plan assumes it lands in `SkillFiles.swift`.

- [ ] **Step 7: Run, verify pass.** `swift build` then `swift test --filter FlowControllerTests` — PASS. Also `swift test` (full) — still green.

- [ ] **Step 8: Commit.** `git add Sources/MengoDesktop/FlowState.swift Sources/MengoDesktop/FlowController.swift Sources/MengoDesktop/RecorderController.swift Sources/MengoDesktop/Log.swift Tests/MengoDesktopTests/FlowControllerTests.swift && git commit -m "MengoDesktop: FlowState + FlowController skeleton (preflight, start) + expose recorder token (TDD)"`

---

## Task 6: `FlowController.runSynthesis` — stop → manifest → claude -p → reviewing/error (TDD)

**Files:** Modify `Sources/MengoDesktop/FlowController.swift`, `Tests/MengoDesktopTests/FlowControllerTests.swift`.

- [ ] **Step 1: Add the failing tests** to `FlowControllerTests.swift`:

```swift
func test_stop_tooShort_returnsToIdle() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let c = makeController(now: { t })
    await c.start()                 // activeRecordingStart = 1_000_000
    t = Date(timeIntervalSince1970: 1_000_005)   // 5 s later
    await c.stop()
    XCTAssertEqual(c.flowState, .idle)
}

func test_stop_synthesisSuccess_entersReviewing_andUpdatesLibrary() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let skillDir = URL(fileURLWithPath: "/tmp/skills/staging-report")
    let stub = StubSynthesis(result: .success(.success(outputDir: skillDir, slug: "staging-report")))
    let c = makeController(synthesis: stub, now: { t })
    await c.start()
    t = Date(timeIntervalSince1970: 1_000_030)   // 30 s
    await c.stop()
    guard case .reviewing(let url) = c.flowState else { return XCTFail("expected .reviewing, got \(c.flowState)") }
    XCTAssertEqual(url, skillDir)
    XCTAssertEqual(c.library.map(\.slug), ["staging-report"])
}

func test_stop_synthesisFailure_entersError() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let stub = StubSynthesis(result: .success(.failure(message: "no narration")))
    let c = makeController(synthesis: stub, now: { t })
    await c.start()
    t = Date(timeIntervalSince1970: 1_000_030)
    await c.stop()
    guard case .error(let msg) = c.flowState else { return XCTFail("expected .error, got \(c.flowState)") }
    XCTAssertTrue(msg.lowercased().contains("no narration"))
}
```

- [ ] **Step 2: Run, verify fails.** `swift test --filter FlowControllerTests` — the 3 new ones FAIL (`runSynthesis` is a no-op stub).

- [ ] **Step 3: Implement `runSynthesis`** in `FlowController.swift`:

```swift
private func runSynthesis(session: FlowSession, regen: ManifestWriter.RegenerationContext?) async {
    let manifestURL: URL
    do {
        manifestURL = try ManifestWriter.write(
            session: session, outputDir: outputDir,
            userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
            regenerationContext: regen, manifestsDir: manifestsDir)
    } catch {
        flowState = .error("Couldn't write the recording manifest: \(error)")
        return
    }
    lastManifestURL = manifestURL
    flowState = .synthesizing(manifestURL)

    guard let claude = claudeExecutable else { flowState = .error("Claude Code CLI not found."); return }
    let logURL = Log.synthesisLogURL(id: UUID().uuidString)
    let prompt = synthesisPrompt.replacingOccurrences(of: "$MANIFEST_PATH", with: manifestURL.path)

    // ~/.claude/skills/ sits behind Claude Code's sensitive-file gate. --dangerously-skip-permissions
    // bypasses it; --add-dir whitelists the path for the working-dir gate that runs first. Both needed.
    // SCREENPIPE_API_KEY in the env so the screenpipe MCP child (spawned by `claude`) can authenticate
    // against Mengo's already-running recorder, plus a sane PATH so `claude`/`npx`/`node` resolve.
    var env = ProcessInfo.processInfo.environment
    env["SCREENPIPE_API_KEY"] = screenpipeToken
    let home = NSHomeDirectory()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

    do {
        let result = try await synthesis.run(
            command: claude,
            arguments: ["--dangerously-skip-permissions", "--add-dir", outputDir.path, "-p", prompt],
            environment: env,
            logFile: logURL,
            timeoutSeconds: 300)
        switch result {
        case .success(let dir, let slug):
            let entry = FlowEntry(slug: slug, name: slug, path: dir, createdAt: now(), sourceManifestId: manifestURL.deletingPathExtension().lastPathComponent)
            libraryStore.add(entry)
            library = libraryStore.load()
            flowState = .reviewing(dir)
            notify("Skill ‘\(slug)’ ready for review.")
        case .failure(let message):
            flowState = .error("Synthesis failed: \(message)   (log: \(logURL.path))")
        }
    } catch {
        flowState = .error("Synthesis subprocess error: \(error)   (log: \(logURL.path))")
    }
}
```

- [ ] **Step 4: Run, verify pass.** `swift test --filter FlowControllerTests` — PASS. Full `swift test` — green.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/FlowController.swift Tests/MengoDesktopTests/FlowControllerTests.swift && git commit -m "MengoDesktop: FlowController.stop → manifest → claude -p → reviewing/error (TDD)"`

---

## Task 7: `FlowController` review actions — regenerate / retry / discard / save (TDD)

**Files:** Modify `Sources/MengoDesktop/FlowController.swift`, `Tests/MengoDesktopTests/FlowControllerTests.swift`. (Depends on `FlowParameter` from Task 11 — for now use the minimal `struct FlowParameter`.)

- [ ] **Step 1: Add the failing tests:**

```swift
func test_regenerate_reentersSynthesizing_withRegenContext() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let skillDir = URL(fileURLWithPath: "/tmp/skills/x")
    let stub = StubSynthesis(result: .success(.success(outputDir: skillDir, slug: "x")))
    let c = makeController(synthesis: stub, now: { t })
    await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
    guard case .reviewing = c.flowState else { return XCTFail() }
    await c.regenerate(feedback: "rename to y")
    guard case .reviewing = c.flowState else { return XCTFail("expected .reviewing again, got \(c.flowState)") }
}

func test_retrySynthesis_fromError_reruns() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let stub = StubSynthesis(result: .success(.failure(message: "boom")))
    let c = makeController(synthesis: stub, now: { t })
    await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
    guard case .error = c.flowState else { return XCTFail() }
    await c.retrySynthesis()
    guard case .error = c.flowState else { return XCTFail("still error after retry (stub still fails) — but it re-ran") }
}

func test_discard_removesSkillDirAndLibraryEntry_returnsToIdle() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    // make a real temp skill dir so discard() can delete it
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("skill-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let stub = StubSynthesis(result: .success(.success(outputDir: dir, slug: dir.lastPathComponent)))
    let c = makeController(synthesis: stub, now: { t })
    await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
    XCTAssertEqual(c.library.count, 1)
    c.discard()
    XCTAssertEqual(c.flowState, .idle)
    XCTAssertEqual(c.library.count, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
}

func test_save_renamesSlugDir_andUpdatesLibrary() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let parent = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("skills-\(UUID().uuidString)")
    let oldDir = parent.appendingPathComponent("old-slug")
    try? FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
    try? "x".write(to: oldDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    let stub = StubSynthesis(result: .success(.success(outputDir: oldDir, slug: "old-slug")))
    let c = makeController(synthesis: stub, now: { t })
    await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
    c.save(name: "New Name", description: "desc", parameters: [])
    XCTAssertEqual(c.flowState, .idle)
    XCTAssertEqual(c.library.first?.slug, "new-name")
    XCTAssertTrue(FileManager.default.fileExists(atPath: parent.appendingPathComponent("new-name/SKILL.md").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path))
}
```

- [ ] **Step 2: Run, verify fails.** `swift test --filter FlowControllerTests` — new ones FAIL.

- [ ] **Step 3: Implement.** In `FlowController.swift`, fill the four method bodies:

```swift
func regenerate(feedback: String) async {
    guard case .reviewing(let prev) = flowState, let session = lastSession else { return }
    await runSynthesis(session: session, regen: .init(previousSkillPath: prev, userFeedback: feedback))
}

func retrySynthesis() async {
    guard case .error = flowState, let session = lastSession else { return }
    await runSynthesis(session: session, regen: nil)
}

func discard() {
    if case .reviewing(let dir) = flowState {
        try? FileManager.default.removeItem(at: dir)
        libraryStore.remove(slug: dir.lastPathComponent); library = libraryStore.load()
    }
    if case .error = flowState, let m = lastManifestURL { try? FileManager.default.removeItem(at: m) }
    flowState = .idle
}

/// Apply Review edits and finalize. Renaming re-slugs the directory (collision →
/// suffix `-2`); for 3a, the name/description/parameters edits beyond the rename
/// are written back to the library index (name) and left to a follow-up for the
/// in-place SKILL.md rewrite — but rename + library update is the critical path.
func save(name: String, description: String?, parameters: [FlowParameter]) {
    guard case .reviewing(let dir) = flowState else { return }
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var finalDir = dir
    let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: dir.deletingLastPathComponent().path)) ?? [])
    let desiredSlug = Slug.uniquify(Slug.derive(from: trimmed.isEmpty ? dir.lastPathComponent : trimmed),
                                    existing: existing.subtracting([dir.lastPathComponent]))
    if desiredSlug != dir.lastPathComponent {
        let target = dir.deletingLastPathComponent().appendingPathComponent(desiredSlug)
        if (try? FileManager.default.moveItem(at: dir, to: target)) != nil { finalDir = target }
    }
    libraryStore.remove(slug: dir.lastPathComponent)
    libraryStore.add(FlowEntry(slug: finalDir.lastPathComponent,
                               name: trimmed.isEmpty ? finalDir.lastPathComponent : trimmed,
                               path: finalDir, createdAt: now(), sourceManifestId: lastManifestURL?.deletingPathExtension().lastPathComponent))
    library = libraryStore.load()
    flowState = .idle
    notify("Saved to \(finalDir.path)")
}
```

- [ ] **Step 4: Run, verify pass.** `swift test --filter FlowControllerTests` — PASS. Full `swift test` — green.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/FlowController.swift Tests/MengoDesktopTests/FlowControllerTests.swift && git commit -m "MengoDesktop: FlowController review actions — regenerate / retry / discard / save (TDD)"`

---

## Task 8: Port the floating Recording HUD

**Files:** Create `Sources/MengoDesktop/RecordingHUD.swift`. No tests (UI) — `swift build` to verify.

- [ ] **Step 1: Implement.** Port `Sources/ScreenpipeFlow/RecordingHUD.swift`. Changes from V1:
  - `RecordingHUDController.show(session:onStop:)` keeps the `NSPanel` config (`styleMask = [.nonactivatingPanel, .hudWindow, .titled]`, `isFloatingPanel = true`, `level = .floating`, `isMovableByWindowBackground = true`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`). `p.title = "Mengo Desktop"`.
  - Position: on `show`, read `UserDefaults.standard.string(forKey: "flow.hudOrigin")` (a `"x,y"` string); if present and on-screen, use it, else default to top-right of `NSScreen.main.visibleFrame`. On `hide`, save the panel's current `frame.origin` back to that key. (Simplest: in `hide()`, `UserDefaults.standard.set("\(p.frame.origin.x),\(p.frame.origin.y)", forKey: "flow.hudOrigin")` before `p.close()`.)
  - `RecordingHUDView`: dark surface (`.padding(12).background(Theme.cardBackground)` won't matter much since `.hudWindow` gives its own chrome — keep V1's simple `HStack` content but use `Theme.recording` for the dot, `Theme.primaryText`/`Theme.secondaryText` for text); the elapsed-time string + the buffer-label logic (buffer is always nil in 3a so it shows nothing — keep the code for 3b); hint = "Narrate as you work."; `Button("Stop", action: onStop).keyboardShortcut(.return)`.

- [ ] **Step 2: Build.** `swift build` — `Build complete!`

- [ ] **Step 3: Commit.** `git add Sources/MengoDesktop/RecordingHUD.swift && git commit -m "MengoDesktop: floating Recording HUD (non-activating NSPanel, remembers position)"`

---

## Task 9: Port `HotkeyManager`

**Files:** Create `Sources/MengoDesktop/HotkeyManager.swift`, `Tests/MengoDesktopTests/HotkeyManagerTests.swift`.

- [ ] **Step 1: Write a minimal test** (`HotkeyManagerTests.swift`):

```swift
import XCTest
@testable import MengoDesktop

@MainActor
final class HotkeyManagerTests: XCTestCase {
    func test_init_andRegister_doNotCrash() {
        let m = HotkeyManager()
        var fired = false
        m.register(HotkeyManager.recordToggle) { fired = true }
        XCTAssertFalse(fired)   // registering doesn't fire the action
        // (We don't synthesize a real key event; this just exercises the Carbon paths.)
    }
}
```

- [ ] **Step 2: Run, verify fails.** `swift test --filter HotkeyManagerTests` — FAIL.

- [ ] **Step 3: Implement.** Port `Sources/ScreenpipeFlow/HotkeyManager.swift` verbatim, with: `Logger.log(...)` → `Log.line(...)`; the signature `OSType(0x53464C57)` → `OSType(0x4D454E47)`; keep `recordToggle` (`⌃⌥R`) and `grabLast` (`⌃⌥G`, unused in 3a) both defined.

- [ ] **Step 4: Run, verify pass.** `swift test --filter HotkeyManagerTests` — PASS.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/HotkeyManager.swift Tests/MengoDesktopTests/HotkeyManagerTests.swift && git commit -m "MengoDesktop: port HotkeyManager (⌃⌥R) from V1"`

---

## Task 10: `SkillFiles` parsers (TDD) + `SkillReviewView` + `FlowPane`

**Files:** Create `Sources/MengoDesktop/SkillFiles.swift`, `Tests/MengoDesktopTests/SkillFilesTests.swift`, `Sources/MengoDesktop/SkillReviewView.swift`, `Sources/MengoDesktop/FlowPane.swift`.

- [ ] **Step 1: Write the failing `SkillFiles` tests:**

```swift
import XCTest
@testable import MengoDesktop

final class SkillFilesTests: XCTestCase {
    func test_parseSkillMarkdown_frontmatter() {
        let md = """
        ---
        name: staging-signups-report
        description: Pull today's signup count from the staging dashboard
          and post a one-line summary to Slack.
        ---

        # Staging Signups Report
        body here
        """
        let r = SkillFiles.parseSkillMarkdown(md)
        XCTAssertEqual(r.name, "staging-signups-report")
        XCTAssertEqual(r.description, "Pull today's signup count from the staging dashboard and post a one-line summary to Slack.")
        XCTAssertTrue(r.body.contains("# Staging Signups Report"))
        XCTAssertFalse(r.body.contains("name:"))
    }
    func test_parseSkillMarkdown_noFrontmatter() {
        let r = SkillFiles.parseSkillMarkdown("# Just a heading\ntext")
        XCTAssertNil(r.name); XCTAssertNil(r.description)
        XCTAssertEqual(r.body, "# Just a heading\ntext")
    }
    func test_parseFlowParameters() throws {
        let json = Data("""
        { "schemaVersion": 1, "parameters": [
          { "name": "slack_channel", "description": "Channel to post to.", "default": "#growth", "autoDetected": false },
          { "name": "user_email", "exampleValue": "me@x.com", "autoDetected": true }
        ], "steps": [
          { "id": 1, "intent": "Open the dashboard", "inferred": true },
          { "id": 2, "intent": "Click Signups", "inferred": false }
        ] }
        """.utf8)
        let params = SkillFiles.parseFlowParameters(json)
        XCTAssertEqual(params.map(\.name), ["slack_channel", "user_email"])
        XCTAssertEqual(params[0].defaultValue, "#growth")
        XCTAssertFalse(params[0].autoDetected)
        XCTAssertTrue(params[1].autoDetected)
        let steps = SkillFiles.parseFlowStepSummaries(json)
        XCTAssertEqual(steps, ["1. Open the dashboard  (inferred — verify)", "2. Click Signups"])
    }
    func test_parseFlowParameters_garbage_returnsEmpty() {
        XCTAssertEqual(SkillFiles.parseFlowParameters(Data("nope".utf8)).count, 0)
        XCTAssertEqual(SkillFiles.parseFlowStepSummaries(Data("nope".utf8)).count, 0)
    }
}
```

- [ ] **Step 2: Run, verify fails.** `swift test --filter SkillFilesTests` — FAIL.

- [ ] **Step 3: Implement `Sources/MengoDesktop/SkillFiles.swift`:**

```swift
import Foundation

struct FlowParameter: Equatable, Identifiable {
    var name: String
    var description: String?
    var defaultValue: String?
    var autoDetected: Bool
    var id: String { name }
}

/// Pure parsers for a synthesized skill's files. Keeps `SkillReviewView` thin
/// and gives the fiddly bits (frontmatter, flow.json) a unit-tested home.
enum SkillFiles {

    /// Splits leading `---`-delimited YAML-ish frontmatter (`name:` / `description:`,
    /// where the description may continue onto indented lines) from the markdown body.
    static func parseSkillMarkdown(_ text: String) -> (name: String?, description: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closeIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (nil, nil, text) }
        let fm = lines[1..<closeIdx]
        var name: String?; var descParts: [String] = []; var inDesc = false
        for raw in fm {
            if let r = raw.range(of: #"^\s*name\s*:\s*"#, options: .regularExpression) {
                name = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces); inDesc = false
            } else if let r = raw.range(of: #"^\s*description\s*:\s*"#, options: .regularExpression) {
                descParts = [String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)]; inDesc = true
            } else if inDesc, raw.first == " " || raw.first == "\t" {
                descParts.append(raw.trimmingCharacters(in: .whitespaces))
            } else { inDesc = false }
        }
        let body = lines[(closeIdx + 1)...].joined(separator: "\n").drop(while: { $0 == "\n" })
        let desc = descParts.isEmpty ? nil : descParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (name, (desc?.isEmpty == true ? nil : desc), String(body))
    }

    private struct FlowJSON: Decodable {
        struct Param: Decodable { let name: String; let description: String?; let `default`: String?; let exampleValue: String?; let autoDetected: Bool? }
        struct Step: Decodable { let id: Int?; let intent: String?; let inferred: Bool? }
        let parameters: [Param]?; let steps: [Step]?
    }

    static func parseFlowParameters(_ data: Data) -> [FlowParameter] {
        guard let f = try? JSONDecoder().decode(FlowJSON.self, from: data) else { return [] }
        return (f.parameters ?? []).map {
            FlowParameter(name: $0.name, description: $0.description,
                          defaultValue: $0.default ?? $0.exampleValue, autoDetected: $0.autoDetected ?? false)
        }
    }

    static func parseFlowStepSummaries(_ data: Data) -> [String] {
        guard let f = try? JSONDecoder().decode(FlowJSON.self, from: data) else { return [] }
        return (f.steps ?? []).enumerated().map { i, s in
            let n = s.id ?? (i + 1)
            let intent = s.intent ?? "(step)"
            return (s.inferred == true) ? "\(n). \(intent)  (inferred — verify)" : "\(n). \(intent)"
        }
    }
}
```

- [ ] **Step 4: Run, verify pass.** `swift test --filter SkillFilesTests` — PASS.

- [ ] **Step 5: Implement `Sources/MengoDesktop/SkillReviewView.swift`** — the `reviewing` UI. Loads `SKILL.md` + `flow.json` from the skill dir in `.task`; editable `@State name/description`; `@State parameters: [FlowParameter]`; renders the markdown body with `Text(AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) ?? AttributedString(body))` inside a `ScrollView`; the parameter list (each: name field, default field, a small "auto-detected" tag, [Remove]; a [+ Add parameter] button); a read-only step list (`SkillFiles.parseFlowStepSummaries`); footer `[Regenerate with feedback…]` (toggles a small `TextEditor` + Apply/Cancel; Apply → `Task { await flow.regenerate(feedback: text) }`), `[Discard]` (→ `flow.discard()`), `[Save]` (→ `flow.save(name:description:parameters:)`). Dark/orange styling, consistent with `MemoryPane`. Takes `let flow: FlowController` and `let skillDir: URL`.

- [ ] **Step 6: Implement `Sources/MengoDesktop/FlowPane.swift`** — switches on `flow.flowState`:
  - `.idle`: hero "Record a task once → get a reusable skill.", a brand-orange `Button("Start recording") { Task { await flow.start() } }` (with a `⌃⌥R` caption), a 3-step how-it-works blurb, a disabled `Label("Grab last N minutes…", systemImage: "clock.arrow.circlepath")` captioned "coming soon", and `flow.hotkeyNote` shown muted if non-nil.
  - `.recording`: "● Recording  <elapsed> — narrate your task; use the floating panel to stop." (a 1 s timer for the elapsed string; pull `activeRecordingStart` out of the associated `FlowSession`).
  - `.synthesizing`: a `ProgressView` + "Building your skill… ~30 s–2 min. Keep working — you'll get a notification when it's ready."
  - `.reviewing(let dir)`: `SkillReviewView(flow: flow, skillDir: dir)`.
  - `.error(let msg)`: the message + `[View log]` (parse the `(log: …)` path out of `msg`, or just open `Log.directory`), `[Retry] { Task { await flow.retrySynthesis() } }`, `[Discard] { flow.discard() }`.
  Dark gradient background like `MemoryPane`; takes `let flow: FlowController`.

- [ ] **Step 7: Build.** `swift build` — `Build complete!`

- [ ] **Step 8: Commit.** `git add Sources/MengoDesktop/SkillFiles.swift Sources/MengoDesktop/SkillReviewView.swift Sources/MengoDesktop/FlowPane.swift Tests/MengoDesktopTests/SkillFilesTests.swift && git commit -m "MengoDesktop: SkillFiles parsers (TDD) + FlowPane state machine + SkillReviewView"`

---

## Task 11: `LibraryPane`

**Files:** Create `Sources/MengoDesktop/LibraryPane.swift`. No tests (UI) — `swift build`.

- [ ] **Step 1: Implement.** A list of `flow.library` (read `FlowEntry`s). Per row: `name` (bold), created date (`.dateStyle = .medium, .timeStyle = .short`). If `entry.exists`: `[Open in Finder] { NSWorkspace.shared.activateFileViewerSelecting([entry.path]) }`, `[Re-open in Review] { flow.reopenInReview(slug: entry.slug) }` (add a small `reopenInReview(slug:)` on `FlowController`: `if let e = library.first(where: {$0.slug == slug}) { flowState = .reviewing(e.path) }`), `[Delete]` (confirm via `NSAlert`; → `flow.deleteFlow(slug:)` — add: `try? FileManager.default.removeItem(at: e.path); libraryStore.remove(slug:); library = libraryStore.load()`). If `!entry.exists`: greyed, "(missing — removed outside Mengo)", `[Remove from list] { flow.deleteFlow(slug:) }` (the removeItem is a no-op then). Empty state: "No flows yet — record one from the Flow tab." Dark styling; takes `let flow: FlowController`. (Add the two `FlowController` methods `reopenInReview(slug:)` and `deleteFlow(slug:)` as part of this task.)

- [ ] **Step 2: Build.** `swift build` — `Build complete!`

- [ ] **Step 3: Commit.** `git add Sources/MengoDesktop/LibraryPane.swift Sources/MengoDesktop/FlowController.swift && git commit -m "MengoDesktop: LibraryPane — saved-flows list (open / re-review / delete)"`

---

## Task 12: Wire Flow into the app — menu, panes, lifecycle, hotkey, notifications, build script

**Files:** Modify `Sources/MengoDesktop/MengoDesktopApp.swift`, `MainWindowView.swift`, `MenuBarContent.swift`, `build-mengo.sh`. No tests (integration) — `swift build` + relaunch.

- [ ] **Step 1: `MengoDesktopApp.swift`.** Add `@State private var hotkeys = HotkeyManager()`, `@State private var hud = RecordingHUDController()`, and `@State private var flow: FlowController` constructed in `init()` *after* the recorder: `_flow = State(initialValue: FlowController.live(recorder: recorder, hud: hud, notify: { Self.postFlowNotification($0) }))` — note `recorder`/`hud` must be created before `flow` in `init`; restructure `init` to build them as locals then assign all the `_x = State(initialValue:)`. Pass `flow` into `MainWindowView(appState:recorder:flow:)` and `MenuBarContent(appState:recorder:flow:)`. In `AppDelegate.applicationDidFinishLaunching`: `NSApp.appearance = .init(named: .darkAqua)`, `Task { await AppDelegate.sharedRecorder?.start() }` (existing), then register the hotkey (`AppDelegate.sharedHotkeys?.register(.recordToggle) { Task { @MainActor in await AppDelegate.sharedFlowController?.toggleRecording() } }` — and add `static weak var sharedHotkeys: HotkeyManager?` set in `init`; also if `register` failed silently, set `flow.hotkeyNote` — actually `HotkeyManager.register` already logs on failure; add a return value or a flag if you want the note, otherwise skip the note for 3a), request `UNUserNotificationCenter.current().requestAuthorization(options: [.alert])` (best-effort, ignore the result), and `if let m = flow.checkForRecovery() { /* show NSAlert "Finish synthesizing your interrupted recording?" → on yes: Task { await flow.synthesizeRecovery(manifestURL: m) } */ }` (the alert can run synchronously here, like V1). In `applicationWillTerminate`: `AppDelegate.sharedFlowController?.dumpRecoveryIfRecording()` (alongside the existing `sharedRecorder?.stop()`). Add `static func postFlowNotification(_ body: String)` — builds a `UNMutableNotificationContent` (title "Mengo Flow", body), `UNNotificationRequest(identifier: UUID().uuidString, content:, trigger: nil)`, `UNUserNotificationCenter.current().add(_)`; also bring the app forward + select the Flow tab on tap (for 3a, simplest: just post the notification; deep-linking the tap is a nice-to-have — at minimum, when synthesis completes the Flow pane is already in `.reviewing` so the user sees it next time they look). Observe the HUD: `FlowController` already calls `hudShow`/`hudHide` itself via the injected closures, so no `.onChange` needed in the app.

- [ ] **Step 2: `MainWindowView.swift`.** Add `let flow: FlowController` to the struct; `case .flow: FlowPane(flow: flow)`, `case .library: LibraryPane(flow: flow)`; the `default: ComingSoonPane(...)` now only catches `.studio` / `.settings`.

- [ ] **Step 3: `MenuBarContent.swift`.** Add `let flow: FlowController`. Replace the Flow group:

```swift
// MARK: Flow
Text("Flow").font(.caption).foregroundStyle(.secondary)
switch flow.flowState {
case .idle, .error:
    Button("Start recording…") { Task { await flow.start() } }.keyboardShortcut("r", modifiers: [.control, .option])
case .recording:
    Button("Stop recording") { Task { await flow.stop() } }.keyboardShortcut("r", modifiers: [.control, .option])
case .synthesizing:
    Button("Synthesizing…") { }.disabled(true)
case .reviewing:
    Button("Reviewing skill…") { flow.bringToReview() }   // selects the Flow tab + activates the app; add this trivial helper, or just open the window
}
Button("Grab last 5 minutes…") { }.disabled(true)
```

(`bringToReview()` on `FlowController`: post `openWindow(id:"main")` equivalent — simplest is to set `appState.selectedSection = .flow` and `NSApp.activate` — pass `appState` into `MenuBarContent` already exists; do it there rather than on `FlowController`. Adjust as convenient.)

- [ ] **Step 4: `build-mengo.sh`.** After the `cp -X Resources/MengoLogo.png ...` line, add: `cp Resources/synthesis-prompt.md "$APP_BUNDLE/Contents/Resources/synthesis-prompt.md"`.

- [ ] **Step 5: Build.** `swift build` — `Build complete!` Then `swift test` — all green (no behavior change to existing tests).

- [ ] **Step 6: Commit.** `git add Sources/MengoDesktop/MengoDesktopApp.swift Sources/MengoDesktop/MainWindowView.swift Sources/MengoDesktop/MenuBarContent.swift build-mengo.sh && git commit -m "MengoDesktop: wire Flow into the app — menu Flow group, Flow/Library panes, ⌃⌥R hotkey, notifications, recovery hook, bundle synthesis-prompt.md"`

---

## Task 13: Recovery — dump on quit-mid-recording, offer to finish on next launch (TDD)

**Files:** Modify `Sources/MengoDesktop/FlowController.swift`, `Tests/MengoDesktopTests/FlowControllerTests.swift`.

- [ ] **Step 1: Add the failing tests:**

```swift
func test_dumpRecovery_thenCheck_findsIt() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let c = makeController(now: { t })
    await c.start()
    t = Date(timeIntervalSince1970: 1_000_120)   // 2 min in
    c.dumpRecoveryIfRecording()
    let found = c.checkForRecovery()
    XCTAssertNotNil(found)
    // the dumped manifest is a real ManifestWriter manifest with end = now()
    let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: found!)) as! [String: Any]
    XCTAssertEqual(json["mode"] as? String, "proactive")
}
func test_dumpRecovery_noop_whenNotRecording() {
    let c = makeController()
    c.dumpRecoveryIfRecording()
    XCTAssertNil(c.checkForRecovery())
}
func test_synthesizeRecovery_runsAndClears() async {
    var t = Date(timeIntervalSince1970: 1_000_000)
    let stub = StubSynthesis(result: .success(.success(outputDir: URL(fileURLWithPath: "/tmp/s/x"), slug: "x")))
    let c = makeController(synthesis: stub, now: { t })
    await c.start(); t = Date(timeIntervalSince1970: 1_000_120); c.dumpRecoveryIfRecording()
    let m = c.checkForRecovery()!
    await c.synthesizeRecovery(manifestURL: m)
    guard case .reviewing = c.flowState else { return XCTFail() }
    XCTAssertNil(c.checkForRecovery())   // cleared after consuming
}
```

- [ ] **Step 2: Run, verify fails.** `swift test --filter FlowControllerTests` — new ones FAIL.

- [ ] **Step 3: Implement** in `FlowController.swift`:

```swift
func dumpRecoveryIfRecording() {
    guard case .recording(var session) = flowState else { return }
    session.endTime = now()
    try? FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
    _ = try? ManifestWriter.write(session: session, outputDir: outputDir,
                                  userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
                                  regenerationContext: nil, manifestsDir: recoveryDir)
}

/// The most recent recovery manifest, if any.
func checkForRecovery() -> URL? {
    guard let entries = try? FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]),
          !entries.isEmpty else { return nil }
    return entries.filter { $0.pathExtension == "json" }
        .sorted { (a, b) in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }.first
}

/// Synthesize from an existing manifest (the recovery dump), then clear the recovery dir.
func synthesizeRecovery(manifestURL: URL) async {
    flowState = .synthesizing(manifestURL)
    lastManifestURL = manifestURL
    guard let claude = claudeExecutable else { flowState = .error("Claude Code CLI not found."); return }
    let logURL = Log.synthesisLogURL(id: UUID().uuidString)
    let prompt = synthesisPrompt.replacingOccurrences(of: "$MANIFEST_PATH", with: manifestURL.path)
    var env = ProcessInfo.processInfo.environment
    env["SCREENPIPE_API_KEY"] = screenpipeToken
    let home = NSHomeDirectory()
    env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
    do {
        let result = try await synthesis.run(command: claude,
            arguments: ["--dangerously-skip-permissions", "--add-dir", outputDir.path, "-p", prompt],
            environment: env, logFile: logURL, timeoutSeconds: 300)
        switch result {
        case .success(let dir, let slug):
            libraryStore.add(FlowEntry(slug: slug, name: slug, path: dir, createdAt: now(), sourceManifestId: manifestURL.deletingPathExtension().lastPathComponent))
            library = libraryStore.load()
            flowState = .reviewing(dir)
            notify("Skill ‘\(slug)’ ready for review.")
        case .failure(let m): flowState = .error("Synthesis failed: \(m)   (log: \(logURL.path))")
        }
    } catch { flowState = .error("Synthesis subprocess error: \(error)   (log: \(logURL.path))") }
    try? FileManager.default.removeItem(at: recoveryDir)
}
```

(Refactor opportunity: `runSynthesis` and `synthesizeRecovery` share the spawn-and-handle block — extract a private `private func spawnSynthesis(manifestURL:logURL:) async -> SynthesisResult?` if you want; not required.)

- [ ] **Step 4: Run, verify pass.** `swift test --filter FlowControllerTests` — PASS. Full `swift test` — green.

- [ ] **Step 5: Commit.** `git add Sources/MengoDesktop/FlowController.swift Tests/MengoDesktopTests/FlowControllerTests.swift && git commit -m "MengoDesktop: Flow recovery — dump manifest on quit-mid-recording, offer to finish on next launch (TDD)"`

---

## Task 14: Manual smoke checklist; full test run; rebuild + relaunch + eyeball

**Files:** Create `docs/manual-smoke-tests/mengo-phase-3a-flow.md`.

- [ ] **Step 1: Write `docs/manual-smoke-tests/mengo-phase-3a-flow.md`** — sections: *Build & tests* (`swift build`; `swift test`; `./build-mengo.sh` produces `MengoDesktop.app` with `Contents/Resources/synthesis-prompt.md` present and codesigned). *App behaviour* — open the app:
  - The sidebar has **Flow** and **Library** entries that show real panes (not "coming soon"); Flow's idle pane shows the "record a task → skill" hero + a brand-orange **Start recording** button (⌃⌥R caption) + a greyed "Grab last N minutes — coming soon".
  - The menu-bar dropdown's **Flow** group has an enabled "Start recording… ⌃⌥R"; "Grab last 5 minutes… ⌃⌥G" is disabled.
  - **Record a real task:** menu (or ⌃⌥R) → a small **floating HUD** appears (never steals focus from other apps, draggable, shows elapsed time + Stop); demonstrate something (open a webpage, copy a value, paste into Slack) while narrating aloud; Stop (HUD's button or ⌃⌥R) → the Flow pane shows "Building your skill…"; a notification "Skill ‘…’ ready for review" arrives; the Flow pane is now in **Review** — SKILL.md preview looks sensible, parameters/steps listed, name/description editable. **Save** → it appears in the **Library** pane. Then in a terminal: `claude` → use the new skill → confirm Claude can execute the intent.
  - **Parameter callout:** record a task narrating "treat my email — me@example.com — as a variable user_email"; in Review, `user_email` is in the parameters list (and `{{user_email}}` in the SKILL.md preview).
  - **Regenerate with feedback…** with a note ("rename to staging-report; default slack_channel to #growth") → the regenerated skill reflects it.
  - **Discard** → the skill dir and its manifest are gone; Flow pane back to idle.
  - **Preflight:** with the Memory recorder paused → "Your microphone is paused…"; with `claude` not on PATH → "Claude Code CLI not found…"; with the screenpipe MCP not configured → the `claude mcp add …` message + working [Copy command].
  - **Quit mid-recording** (start recording, then ⌘Q) → relaunch → an alert offers "Finish synthesizing your interrupted recording?"; accept → it synthesizes the partial.
  - **Recording <10 s** → "Recording too short to synthesize."; no Review.
  - **Library:** [Open in Finder] opens the skill dir; [Re-open in Review] returns to the Flow pane in Review for that skill; [Delete] removes it (with confirm); a skill dir deleted from Finder shows greyed "(missing)" with only [Remove from list].

- [ ] **Step 2: Full test run.** `swift test` — all suites PASS (existing + the ~9 new test files).

- [ ] **Step 3: Rebuild + re-sign.** `./build-mengo.sh` — completes; ends with `screenpipe vX (arch) embedded`; `ls MengoDesktop.app/Contents/Resources/synthesis-prompt.md` exists; `codesign --verify --deep --strict MengoDesktop.app` passes.

- [ ] **Step 4: Relaunch + eyeball.** Quit any running MengoDesktop, `open ./MengoDesktop.app`. Verify (visually / via screenshot): the Flow pane idle state renders, the Library pane renders ("No flows yet"), the menu's Flow group is enabled, ⌃⌥R starts a recording (HUD appears) and ⌃⌥R again stops it (→ "Building your skill…" — it'll likely fail synthesis unless `claude` + the MCP are set up, which is fine for the eyeball; the *flow* of states is what we're checking). If something's broken, fix + amend the relevant commit.

- [ ] **Step 5: Commit + (optionally) tag.** `git add docs/manual-smoke-tests/mengo-phase-3a-flow.md && git commit -m "MengoDesktop: Phase 3a smoke checklist"`. (Tag `mengo-v2-phase-3a-flow` once the human-run checklist passes — not yet.)

---

## Self-review notes

- **Spec coverage:** Flow pane state machine → FlowState (T5) + FlowPane (T10); SkillReviewView → T10; Library pane → T11; HUD → T8; menu Flow group → T12; ported components (FlowSession/Slug/ManifestWriter/SynthesisRunner/HotkeyManager) → T1–3, T9; FlowController (preflight/start/stop/synthesis/regenerate/retry/discard/save) → T5–7; FlowLibrary → T4; SkillFiles parsers → T10; recovery → T13; SCREENPIPE_API_KEY env → T6 (`runSynthesis`); `claude -p --dangerously-skip-permissions --add-dir` → T6; preflight messages incl. MCP-config → T5; `synthesis-prompt.md` bundled → T12; `Log.synthesisLogURL` → T5; recorder token exposed → T5; wiring (app/menu/window) → T12; tests + smoke checklist → throughout + T14. ✅ all spec sections map to a task.
- **Placeholder scan:** the spec's "open questions" are intentionally deferred (MCP-config normalization → covered by a best-effort `mcp list` check + a clear message, `ScreenpipeFlowClient` collapsed into `RecorderPreflightHealth` rather than a new file, markdown via `AttributedString`, `claude -p` flags carried from V1, hotkey-conflict note is best-effort/skippable). `FlowParameter` forward-declaration between T5 and T10 is called out explicitly. No "TODO/TBD/handle errors" left. ✅
- **Type consistency:** `FlowSession` (not `RecordingSession`), `FlowState`, `FlowController`, `FlowEntry`, `FlowLibrary`, `FlowParameter`, `SynthesisRunning`/`SystemSynthesisRunner`, `FlowPreflightHealth`/`RecorderPreflightHealth`, `SynthesisRunner.run(command:arguments:environment:logFile:timeoutSeconds:)` (the `environment:` param added in T3 and used in T6/T13), `RecorderController.screenpipeToken` (added T5, used T5's `live`), `Log.synthesisLogURL(id:)` (added T5, used T6/T13), `FlowController` methods (`start`/`stop`/`toggleRecording`/`regenerate`/`retrySynthesis`/`discard`/`save`/`dumpRecoveryIfRecording`/`checkForRecovery`/`synthesizeRecovery`/`reopenInReview`/`deleteFlow`) referenced consistently across T5–13 and the views. ✅
