import XCTest
@testable import MengoDesktop

@MainActor
final class FlowControllerTests: XCTestCase {

    // MARK: stubs

    struct StubSynthesis: SynthesisRunning {
        var result: SynthesisResult
        func run(command: URL, arguments: [String], environment: [String: String]?,
                 logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult { result }
    }
    final class RecordingSynthesis: SynthesisRunning, @unchecked Sendable {
        var result: SynthesisResult = .failure(message: "stub")
        private(set) var lastCommand: URL?
        private(set) var lastArguments: [String]?
        private(set) var lastEnvironment: [String: String]?
        func run(command: URL, arguments: [String], environment: [String: String]?,
                 logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult {
            lastCommand = command; lastArguments = arguments; lastEnvironment = environment
            return result
        }
    }
    struct StubHealth: FlowPreflightHealth {
        var healthy = true
        var audioPaused = false
        func snapshot() async -> (healthy: Bool, audioPaused: Bool) { (healthy, audioPaused) }
    }
    struct StubMoments: MomentIndexing {
        var moments: [Moment] = []
        func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment] { moments }
    }

    private func tmpDir() -> URL {
        let u = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("flowctl-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    final class StubLoginItem: LoginItemControlling, @unchecked Sendable {
        var enabled = false
        func register() throws { enabled = true }
        func unregister() throws { enabled = false }
        var isEnabled: Bool { enabled }
    }
    private func makeSettings(runtime: SynthesisRuntime = .claudeCode) -> SettingsStore {
        let d = UserDefaults(suiteName: "fc-\(UUID().uuidString)")!
        let s = SettingsStore(defaults: d, loginItem: StubLoginItem())
        s.synthesisRuntime = runtime
        return s
    }

    private func makeController(
        synthesis: SynthesisRunning = StubSynthesis(result: .failure(message: "stub")),
        health: FlowPreflightHealth = StubHealth(),
        moments: MomentIndexing = StubMoments(),
        executableOverride: @escaping (SynthesisRuntime) -> URL? = { _ in URL(fileURLWithPath: "/tmp/does-not-exist-claude") },
        settings: SettingsStore? = nil,
        entitlement: @escaping @MainActor () -> FlowController.Entitlement = { .init(isPro: true, flowLimit: nil) },
        onFlowLimitReached: @escaping @MainActor () -> Void = { },
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_700_000_000) }
    ) -> FlowController {
        let base = tmpDir()
        let st = settings ?? makeSettings()
        return FlowController(
            recorderToken: "sp-test",
            executableOverride: executableOverride,
            synthesisPrompt: "PROMPT $MANIFEST_PATH",
            outputDir: base.appendingPathComponent("skills"),
            manifestsDir: base.appendingPathComponent("manifests"),
            recoveryDir: base.appendingPathComponent("recovery"),
            library: FlowLibrary(fileURL: base.appendingPathComponent("library.json")),
            synthesis: synthesis,
            health: health,
            moments: moments,
            settings: st,
            entitlement: entitlement,
            onFlowLimitReached: onFlowLimitReached,
            now: now,
            hudShow: { _, _ in }, hudHide: { }, notify: { _ in },
            onPreflightFailure: { _ in })
    }

    // MARK: state machine + preflight

    func test_initial_isIdle() { XCTAssertEqual(makeController().flowState, .idle) }

    func test_preflight_pass() async { let r = await makeController().preflight(); XCTAssertNil(r) }
    func test_preflight_recorderUnhealthy() async {
        let r = await makeController(health: StubHealth(healthy: false)).preflight(); XCTAssertEqual(r, .recorderNotRunning)
    }
    func test_preflight_audioPaused() async {
        let r = await makeController(health: StubHealth(audioPaused: true)).preflight(); XCTAssertEqual(r, .audioPaused)
    }
    func test_preflight_runtimeMissing() async {
        let r = await makeController(executableOverride: { _ in nil }).preflight()
        XCTAssertEqual(r, .runtimeNotFound(.claudeCode))
    }
    func test_preflight_codexRuntimeMissing() async {
        let r = await makeController(executableOverride: { _ in nil }, settings: makeSettings(runtime: .codex)).preflight()
        XCTAssertEqual(r, .runtimeNotFound(.codex))
    }

    func test_start_entersRecording() async {
        let c = makeController()
        await c.start()
        guard case .recording = c.flowState else { return XCTFail("expected .recording, got \(c.flowState)") }
    }
    func test_start_blockedByPreflight_staysIdle() async {
        let c = makeController(executableOverride: { _ in nil })   // → .runtimeNotFound; onPreflightFailure is a no-op in tests
        await c.start()
        XCTAssertEqual(c.flowState, .idle)
    }

    // MARK: stop → synthesis

    func test_stop_tooShort_returnsToIdle() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let c = makeController(now: { t })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_005)   // 5 s
        await c.stop()
        XCTAssertEqual(c.flowState, .idle)
    }

    func test_stop_synthesisSuccess_entersReviewing_andUpdatesLibrary() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let skillDir = URL(fileURLWithPath: "/tmp/skills/staging-report")
        let c = makeController(synthesis: StubSynthesis(result: .success(outputDir: skillDir, slug: "staging-report")), now: { t })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_030)
        await c.stop()
        guard case .reviewing(let url) = c.flowState else { return XCTFail("expected .reviewing, got \(c.flowState)") }
        XCTAssertEqual(url, skillDir)
        XCTAssertEqual(c.library.map(\.slug), ["staging-report"])
    }

    func test_stop_synthesisFailure_entersError() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let c = makeController(synthesis: StubSynthesis(result: .failure(message: "no narration")), now: { t })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_030)
        await c.stop()
        guard case .error(let msg) = c.flowState else { return XCTFail("expected .error, got \(c.flowState)") }
        XCTAssertTrue(msg.lowercased().contains("no narration"))
    }

    // MARK: review actions

    func test_regenerate_reentersReviewing() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let dir = URL(fileURLWithPath: "/tmp/skills/x")
        let c = makeController(synthesis: StubSynthesis(result: .success(outputDir: dir, slug: "x")), now: { t })
        await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
        guard case .reviewing = c.flowState else { return XCTFail() }
        await c.regenerate(feedback: "rename to y")
        guard case .reviewing = c.flowState else { return XCTFail("expected .reviewing again, got \(c.flowState)") }
    }

    func test_retrySynthesis_fromError_reruns() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let c = makeController(synthesis: StubSynthesis(result: .failure(message: "boom")), now: { t })
        await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
        guard case .error = c.flowState else { return XCTFail() }
        await c.retrySynthesis()
        guard case .error = c.flowState else { return XCTFail("re-ran but stub still fails — should still be .error") }
    }

    func test_discard_removesSkillDirAndLibraryEntry_returnsToIdle() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("skill-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = makeController(synthesis: StubSynthesis(result: .success(outputDir: dir, slug: dir.lastPathComponent)), now: { t })
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
        let c = makeController(synthesis: StubSynthesis(result: .success(outputDir: oldDir, slug: "old-slug")), now: { t })
        await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
        c.save(name: "New Name", description: "desc", parameters: [])
        XCTAssertEqual(c.flowState, .idle)
        XCTAssertEqual(c.library.first?.slug, "new-name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: parent.appendingPathComponent("new-name/SKILL.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldDir.path))
    }

    // MARK: recovery

    func test_dumpRecovery_thenCheck_findsIt() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let c = makeController(now: { t })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_120)   // 2 min in
        c.dumpRecoveryIfRecording()
        let found = c.checkForRecovery()
        XCTAssertNotNil(found)
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
        let c = makeController(synthesis: StubSynthesis(result: .success(outputDir: URL(fileURLWithPath: "/tmp/s/x"), slug: "x")), now: { t })
        await c.start(); t = Date(timeIntervalSince1970: 1_000_120); c.dumpRecoveryIfRecording()
        let m = c.checkForRecovery()!
        await c.synthesizeRecovery(manifestURL: m)
        guard case .reviewing = c.flowState else { return XCTFail("expected .reviewing, got \(c.flowState)") }
        XCTAssertNil(c.checkForRecovery())   // recovery dir cleared after consuming
    }

    // MARK: Mode C — retroactive ("grab last N minutes")

    func test_beginBrowsingTimeline_fromIdle() {
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
        let t = Date(timeIntervalSince1970: 1_000_000)
        let c = makeController(now: { t })
        c.beginBrowsingTimeline()
        let bufferStart = Date(timeIntervalSince1970: 999_400)   // 10 min earlier
        await c.startRetroactive(bufferStart: bufferStart)
        guard case .recording(let s) = c.flowState else { return XCTFail("expected .recording, got \(c.flowState)") }
        XCTAssertEqual(s.mode, .retroactive)
        XCTAssertEqual(s.bufferRangeStart, bufferStart)
        XCTAssertEqual(s.activeRecordingStart, t)
    }
    func test_startRetroactive_blockedByPreflight_staysBrowsing() async {
        let c = makeController(executableOverride: { _ in nil })   // → .runtimeNotFound; onPreflightFailure is a no-op in tests
        c.beginBrowsingTimeline()
        await c.startRetroactive(bufferStart: Date())
        XCTAssertEqual(c.flowState, .browsingTimeline)
    }
    func test_startRetroactive_noopWhenNotBrowsing() async {
        let c = makeController()
        await c.startRetroactive(bufferStart: Date())   // we're .idle, not .browsingTimeline
        XCTAssertEqual(c.flowState, .idle)
    }
    func test_loadMoments_returnsStubList() async throws {
        let m = [Moment(timestamp: Date(timeIntervalSince1970: 1), appName: "A", windowName: "w")]
        let c = makeController(moments: StubMoments(moments: m))
        let got = try await c.loadMoments(lookbackMinutes: 30)
        XCTAssertEqual(got, m)
    }

    // MARK: runtime dispatch

    func test_synthesize_codexRuntime_issuesCodexCommand() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let stub = RecordingSynthesis()
        stub.result = .success(outputDir: URL(fileURLWithPath: "/tmp/skills/x"), slug: "x")
        // Fake non-existent path so the preflight MCP-list spawn returns false (doesn't block) — same trick the Claude tests use.
        let codexExe = URL(fileURLWithPath: "/tmp/does-not-exist-codex")
        let c = makeController(synthesis: stub,
                               executableOverride: { _ in codexExe },
                               settings: makeSettings(runtime: .codex),
                               now: { t })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_030)
        await c.stop()
        XCTAssertEqual(stub.lastCommand, codexExe)
        XCTAssertEqual(stub.lastArguments?.first, "exec")
        XCTAssertTrue(stub.lastArguments?.contains("--dangerously-bypass-approvals-and-sandbox") ?? false)
    }

    func test_synthesize_claudeRuntime_stillIssuesClaudeCommand() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let stub = RecordingSynthesis()
        stub.result = .success(outputDir: URL(fileURLWithPath: "/tmp/skills/x"), slug: "x")
        let claudeExe = URL(fileURLWithPath: "/tmp/does-not-exist-claude")
        let c = makeController(synthesis: stub, executableOverride: { _ in claudeExe }, now: { t })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_030)
        await c.stop()
        XCTAssertEqual(stub.lastCommand, claudeExe)
        XCTAssertEqual(stub.lastArguments?.first, "--dangerously-skip-permissions")
    }

    // MARK: entitlement / flow-limit gate

    func test_save_blockedAtFreeLimit_doesNotAdd_andCallsCallback() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        // Pre-populate the library with 3 existing entries on disk (via the real store so the JSON encoding matches).
        let parent = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("skills-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let libFile = parent.appendingPathComponent("library.json")
        let preStore = FlowLibrary(fileURL: libFile)
        for i in 0..<3 {
            let d = parent.appendingPathComponent("pre-\(i)")
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            try? "x".write(to: d.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
            preStore.add(FlowEntry(slug: "pre-\(i)", name: "pre-\(i)", path: d, createdAt: t, sourceManifestId: nil))
        }

        // Build controller manually so its libraryStore points at the seeded file.
        let stub = StubSynthesis(result: .success(outputDir: parent.appendingPathComponent("new-flow"), slug: "new-flow"))
        try? FileManager.default.createDirectory(at: parent.appendingPathComponent("new-flow"), withIntermediateDirectories: true)
        try? "x".write(to: parent.appendingPathComponent("new-flow/SKILL.md"), atomically: true, encoding: .utf8)
        var hit = false
        let c = FlowController(
            recorderToken: "sp-test",
            executableOverride: { _ in URL(fileURLWithPath: "/tmp/nonex") },
            synthesisPrompt: "PROMPT $MANIFEST_PATH",
            outputDir: parent,
            manifestsDir: parent.appendingPathComponent("m"),
            recoveryDir: parent.appendingPathComponent("r"),
            library: FlowLibrary(fileURL: libFile),
            synthesis: stub,
            health: StubHealth(),
            moments: StubMoments(),
            settings: makeSettings(),
            entitlement: { .init(isPro: false, flowLimit: 3) },
            onFlowLimitReached: { hit = true },
            now: { t },
            hudShow: { _, _ in }, hudHide: { }, notify: { _ in },
            onPreflightFailure: { _ in })
        await c.start()
        t = Date(timeIntervalSince1970: 1_000_030)
        await c.stop()
        // After stop+synthesis success, .reviewing with the new dir; library now has 4 (the existing 3 + the newly-added unsaved synthesis entry).
        guard case .reviewing = c.flowState else { return XCTFail("expected .reviewing, got \(c.flowState)") }
        // Save should be blocked — library count stays at 4 (3 pre + 1 synthesis-added), state stays .reviewing.
        c.save(name: "blocked", description: nil, parameters: [])
        XCTAssertTrue(hit, "onFlowLimitReached should fire")
        guard case .reviewing = c.flowState else { return XCTFail("save should not change state when blocked") }
    }

    func test_save_allowedWhenPro() async {
        var t = Date(timeIntervalSince1970: 1_000_000)
        let parent = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("skills-\(UUID().uuidString)")
        let oldDir = parent.appendingPathComponent("old-slug")
        try? FileManager.default.createDirectory(at: oldDir, withIntermediateDirectories: true)
        try? "x".write(to: oldDir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        let c = makeController(synthesis: StubSynthesis(result: .success(outputDir: oldDir, slug: "old-slug")),
                               entitlement: { .init(isPro: true, flowLimit: nil) }, now: { t })
        await c.start(); t = Date(timeIntervalSince1970: 1_000_030); await c.stop()
        c.save(name: "ok name", description: nil, parameters: [])
        XCTAssertEqual(c.flowState, .idle)
    }
}
