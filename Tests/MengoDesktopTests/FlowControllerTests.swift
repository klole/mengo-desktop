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
        synthesis: SynthesisRunning = StubSynthesis(result: .failure(message: "stub")),
        health: FlowPreflightHealth = StubHealth(),
        claudeExecutable: URL? = URL(fileURLWithPath: "/tmp/does-not-exist-claude"),
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
            hudShow: { _, _ in }, hudHide: { }, notify: { _ in },
            onPreflightFailure: { _ in })
    }

    // MARK: state machine + preflight

    func test_initial_isIdle() { XCTAssertEqual(makeController().flowState, .idle) }

    func test_preflight_pass() async { let r = await makeController().preflight(); XCTAssertNil(r) }
    func test_preflight_screenpipeUnhealthy() async {
        let r = await makeController(health: StubHealth(healthy: false)).preflight(); XCTAssertEqual(r, .screenpipeNotRunning)
    }
    func test_preflight_audioPaused() async {
        let r = await makeController(health: StubHealth(audioPaused: true)).preflight(); XCTAssertEqual(r, .audioPaused)
    }
    func test_preflight_claudeMissing() async {
        let r = await makeController(claudeExecutable: nil).preflight(); XCTAssertEqual(r, .claudeNotFound)
    }

    func test_start_entersRecording() async {
        let c = makeController()
        await c.start()
        guard case .recording = c.flowState else { return XCTFail("expected .recording, got \(c.flowState)") }
    }
    func test_start_blockedByPreflight_staysIdle() async {
        let c = makeController(claudeExecutable: nil)   // → .claudeNotFound; onPreflightFailure is a no-op in tests
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
}
