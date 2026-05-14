import XCTest
@testable import MengoDesktop

private actor StubDashboardSource: MemoryDashboardSource {
    private var topAppsResponse: [RawAppCount] = []
    private var recentFramesResponse: [FrameRow] = []
    private var recentActivityResponse: [ActivityEvent] = []
    private(set) var lastTopAppsWindow: TimeInterval?

    func setTopApps(_ r: [RawAppCount]) { topAppsResponse = r }
    func setRecentFrames(_ r: [FrameRow]) { recentFramesResponse = r }
    func setRecentActivity(_ r: [ActivityEvent]) { recentActivityResponse = r }

    func topApps(window: TimeInterval, limit: Int) async throws -> [RawAppCount] {
        lastTopAppsWindow = window
        return topAppsResponse
    }
    func recentFrames(window: TimeInterval, limit: Int) async throws -> [FrameRow] {
        recentFramesResponse
    }
    func recentActivity(sinceFrameID: Int64, sinceAudioID: Int64, limit: Int) async throws -> [ActivityEvent] {
        recentActivityResponse
    }
    func lastFrameID() async throws -> Int64? { nil }
    func lastAudioID() async throws -> Int64? { nil }
}

private struct StubLoginItem: LoginItemControlling {
    func register() throws {}
    func unregister() throws {}
    var isEnabled: Bool { false }
}

@MainActor
final class MemoryDashboardStoreTests: XCTestCase {

    private func freshSettings() -> SettingsStore {
        let suite = "MengoTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return SettingsStore(defaults: defaults, loginItem: StubLoginItem())
    }

    func test_initialState_isEmpty() async {
        let store = MemoryDashboardStore(db: StubDashboardSource(), settings: freshSettings())
        XCTAssertEqual(store.topApps, [])
        XCTAssertEqual(store.recentSessions, [])
        XCTAssertEqual(store.recentActivity, [])
        XCTAssertEqual(store.topAppsWindow, .today)
    }

    func test_refresh_appliesStubData() async throws {
        let stub = StubDashboardSource()
        await stub.setTopApps([
            RawAppCount(appName: "Chrome", frameCount: 10),
            RawAppCount(appName: "Code", frameCount: 6),
        ])
        let now = Date()
        await stub.setRecentFrames((0..<10).map { i in
            FrameRow(
                id: Int64(i),
                timestamp: now.addingTimeInterval(TimeInterval(i * 30)),
                appName: "Chrome",
                windowName: "Inbox",
                browserURL: nil
            )
        })

        let store = MemoryDashboardStore(db: stub, settings: freshSettings())
        await store.refresh()

        XCTAssertEqual(store.topApps.map(\.appName), ["Chrome", "Code"])
        XCTAssertEqual(store.topApps.first?.sharePercent, 63) // 10/16
        XCTAssertEqual(store.recentSessions.count, 1)
        XCTAssertEqual(store.recentSessions.first?.frameCount, 10)
    }

    func test_setTopAppsWindow_persistsToSettings_andTriggersRefreshWithNewWindow() async throws {
        let stub = StubDashboardSource()
        let settings = freshSettings()
        let store = MemoryDashboardStore(db: stub, settings: settings)

        await store.setTopAppsWindow(.last7Days)

        XCTAssertEqual(settings.topAppsWindow, .last7Days)
        XCTAssertEqual(store.topAppsWindow, .last7Days)

        let observedWindow = await stub.lastTopAppsWindow
        XCTAssertEqual(observedWindow, TopAppsWindow.last7Days.seconds)
    }

    func test_task_consumesActivityStreamAndPrependsBatches() async throws {
        let stub = StubDashboardSource()
        let firstBatch: [ActivityEvent] = [
            .screenshot(id: 1, at: Date(), appName: "Chrome", windowName: nil),
            .screenshot(id: 2, at: Date(), appName: "Chrome", windowName: nil),
        ]
        await stub.setRecentActivity(firstBatch)

        let stream = ActivityFeedStream(source: stub, interval: .milliseconds(5), backoff: .milliseconds(5))
        let store = MemoryDashboardStore(db: stub, settings: freshSettings(), activityStream: stream)

        let task = Task { await store.task() }
        defer { task.cancel() }

        // Wait for the first batch to arrive.
        try await eventually(timeout: .seconds(1)) { store.recentActivity.count == 2 }
        XCTAssertEqual(store.recentActivity.map(\.id), ["screenshot-1", "screenshot-2"])
    }

    func test_task_capsRecentActivityAt100() async throws {
        let stub = StubDashboardSource()
        // 150 events in a single batch — only the newest 100 should remain.
        let many: [ActivityEvent] = (1...150).map { id in
            .screenshot(id: Int64(id), at: Date(), appName: "Chrome", windowName: nil)
        }
        await stub.setRecentActivity(many)

        let stream = ActivityFeedStream(source: stub, interval: .milliseconds(5), backoff: .milliseconds(5))
        let store = MemoryDashboardStore(db: stub, settings: freshSettings(), activityStream: stream)

        let task = Task { await store.task() }
        defer { task.cancel() }

        try await eventually(timeout: .seconds(1)) { store.recentActivity.count > 0 }
        XCTAssertEqual(store.recentActivity.count, 100)
    }

    // MARK: -

    private func eventually(timeout: Duration, predicate: () -> Bool) async throws {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("condition not met within \(timeout)")
    }
}
