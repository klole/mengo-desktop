import XCTest
@testable import MengoDesktop

final class SessionsServiceTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000) // fixed reference

    // Helpers
    private func frame(_ id: Int64, secondsFromNow: TimeInterval, app: String, window: String? = nil) -> FrameRow {
        FrameRow(
            id: id,
            timestamp: now.addingTimeInterval(secondsFromNow),
            appName: app,
            windowName: window,
            browserURL: nil
        )
    }

    // MARK: - Time-clustering

    func test_cluster_mergesAdjacentFramesIntoOneSession() {
        // 10 Chrome frames, 30s apart → one session of duration ~270s.
        let frames = (0..<10).map { i in frame(Int64(i), secondsFromNow: TimeInterval(i * 30), app: "Chrome") }
        let sessions = SessionsService.cluster(frames)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].frameCount, 10)
        XCTAssertEqual(sessions[0].title, "Google Chrome session")
    }

    func test_cluster_splitsOnLargeGap() {
        // 6 Chrome frames over 5min, then 7min gap, then 4 Chrome frames over 3min.
        var frames: [FrameRow] = []
        for i in 0..<6 { frames.append(frame(Int64(i), secondsFromNow: TimeInterval(i * 60), app: "Chrome")) }
        for i in 0..<4 { frames.append(frame(Int64(100 + i), secondsFromNow: TimeInterval(720 + i * 60), app: "Chrome")) }
        let sessions = SessionsService.cluster(frames)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].frameCount, 6)
        XCTAssertEqual(sessions[1].frameCount, 4)
    }

    func test_cluster_keepsDifferentAppsInSameTimeCluster() {
        // Chrome (5 frames) → Slack (3 frames), all within one tight cluster.
        var frames: [FrameRow] = []
        for i in 0..<5 { frames.append(frame(Int64(i), secondsFromNow: TimeInterval(i * 30), app: "Chrome")) }
        for i in 0..<3 { frames.append(frame(Int64(100 + i), secondsFromNow: TimeInterval(150 + i * 30), app: "Slack")) }
        let sessions = SessionsService.cluster(frames)
        XCTAssertEqual(sessions.count, 1, "Different apps within the same time cluster stay in one session")
        XCTAssertEqual(sessions[0].title, "Google Chrome session", "Dominant app labels the session")
        XCTAssertEqual(sessions[0].subtitle, "with Slack")
    }

    func test_cluster_filtersShortSessions() {
        // A 90-second session is dropped (minDuration = 120 by default).
        let frames = [frame(1, secondsFromNow: 0, app: "Chrome"), frame(2, secondsFromNow: 90, app: "Chrome")]
        let sessions = SessionsService.cluster(frames)
        XCTAssertEqual(sessions.count, 0)
    }

    func test_cluster_subtitleIsDominantWindowName() {
        // 7 of 10 frames share window_name "Inbox" → 70% → subtitle is "Inbox".
        var frames: [FrameRow] = []
        for i in 0..<7 { frames.append(frame(Int64(i), secondsFromNow: TimeInterval(i * 30), app: "Chrome", window: "Inbox")) }
        for i in 0..<3 { frames.append(frame(Int64(7 + i), secondsFromNow: TimeInterval((7 + i) * 30), app: "Chrome", window: "Calendar")) }
        let sessions = SessionsService.cluster(frames)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].subtitle, "Inbox")
    }

    func test_cluster_emptyInputReturnsEmpty() {
        XCTAssertEqual(SessionsService.cluster([]), [])
    }

    func test_cluster_appIconsAreTopThreeByCount() {
        // 6 Chrome, 4 Slack, 2 Code, 1 Figma → icons should be [chrome, slack, code].
        var frames: [FrameRow] = []
        for i in 0..<6 { frames.append(frame(Int64(i), secondsFromNow: TimeInterval(i * 20), app: "Chrome")) }
        for i in 0..<4 { frames.append(frame(Int64(100 + i), secondsFromNow: TimeInterval(120 + i * 20), app: "Slack")) }
        for i in 0..<2 { frames.append(frame(Int64(200 + i), secondsFromNow: TimeInterval(200 + i * 20), app: "Code")) }
        frames.append(frame(300, secondsFromNow: 240, app: "Figma"))
        let sessions = SessionsService.cluster(frames)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].appIcons.count, 3)
        // Chrome icon should be first; specific symbol names verified in AppUsageServiceTests.
        XCTAssertEqual(sessions[0].appIcons.first, AppUsageService.iconName(for: "Chrome"))
    }
}
