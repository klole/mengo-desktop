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
}
