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
        private(set) var lastExtraArguments: [String] = []
        var isRunning: Bool { running }
        func start(binaryURL: URL, extraArguments: [String]) throws {
            if shouldFailStart { throw StubError.boom }
            startCount += 1; running = true; lastExtraArguments = extraArguments
        }
        func stop() { stopCount += 1; running = false }
    }

    actor StubAPI: RecorderHealthAPI {
        var shouldFailHealth = false
        private(set) var audioStopCount = 0
        private(set) var audioStartCount = 0
        func setShouldFailHealth(_ v: Bool) { shouldFailHealth = v }
        func health() async throws -> RecorderHealth {
            if shouldFailHealth { throw URLError(.cannotConnectToHost) }
            return RecorderHealth(status: "healthy", frameStatus: "ok", audioStatus: "ok")
        }
        func audioStop() async throws { audioStopCount += 1 }
        func audioStart() async throws { audioStartCount += 1 }
    }

    struct StubCatalog: RecordingSourceCatalog {
        var monitors: [MonitorInfo] = []
        var devices: [AudioDeviceInfo] = []
        func availableMonitors() async throws -> [MonitorInfo] { monitors }
        func availableAudioDevices() async throws -> [AudioDeviceInfo] { devices }
    }

    // MARK: Helpers

    private func freshStore() -> RecordingSourcesStore {
        let name = "MengoTest-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!; d.removePersistentDomain(forName: name)
        return RecordingSourcesStore(defaults: d)
    }

    /// Build a controller wired to stubs — no real recorder / TCC / poll delay.
    private func makeController(process: StubProcess = StubProcess(),
                               api: StubAPI = StubAPI(),
                               store: RecordingSourcesStore? = nil,
                               catalog: RecordingSourceCatalog = StubCatalog(),
                               ensureBinary: @escaping () throws -> URL = { URL(fileURLWithPath: "/tmp/fake-recorder") })
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

    // MARK: Source arguments

    actor CountingCatalog: RecordingSourceCatalog {
        private(set) var monitorCalls = 0
        func availableMonitors() async throws -> [MonitorInfo] { monitorCalls += 1; return [] }
        func availableAudioDevices() async throws -> [AudioDeviceInfo] { [] }
    }

    private func monitor(_ id: Int) -> MonitorInfo {
        MonitorInfo(id: id, name: "D\(id)", width: 100, height: 100, isDefault: id == 1)
    }

    func test_sourceArgs_nilSelection_noMonitorFlags_andCatalogNotConsulted() async {
        let proc = StubProcess()
        let cat = CountingCatalog()
        let c = makeController(process: proc, catalog: cat)   // store left nil → all defaults
        await c.start()
        await eventually { c.status == .recording }
        XCTAssertFalse(proc.lastExtraArguments.contains("--monitor-id"))
        XCTAssertFalse(proc.lastExtraArguments.contains("--disable-audio"))
        let calls = await cat.monitorCalls
        XCTAssertEqual(calls, 0)
    }

    func test_sourceArgs_explicitMonitors_emittedAndValidated() async {
        let store = freshStore(); store.selectedMonitorIDs = [1, 9]    // 9 isn't live
        let proc = StubProcess()
        let c = makeController(process: proc, store: store, catalog: StubCatalog(monitors: [monitor(1)]))
        await c.start()
        await eventually { c.status == .recording }
        XCTAssertEqual(proc.lastExtraArguments, ["--monitor-id", "1"])   // 9 dropped
    }

    func test_sourceArgs_emptyMonitorsAfterValidation_fallsBackToAll() async {
        let store = freshStore(); store.selectedMonitorIDs = [42]       // none live
        let proc = StubProcess()
        let c = makeController(process: proc, store: store, catalog: StubCatalog(monitors: [monitor(1)]))
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
        let cat = StubCatalog(monitors: [monitor(1), monitor(2)])
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
}
