import XCTest
@testable import MengoDesktop

final class InsightsEngineTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_750_000_000) // fixed reference

    private func frame(_ id: Int64, secondsFromNow: TimeInterval, app: String, window: String? = nil) -> FrameRow {
        FrameRow(
            id: id,
            timestamp: now.addingTimeInterval(secondsFromNow),
            appName: app,
            windowName: window,
            browserURL: nil
        )
    }

    // MARK: - App pair / sequence

    func test_detectsRepeatedAppPair() {
        // Chrome → Slack three separate times. Each pair appears within a
        // session, then a gap, then repeat.
        var frames: [FrameRow] = []
        // Burst 1: Chrome 0..60, Slack 90..150.
        for i in 0..<3 { frames.append(frame(Int64(i),       secondsFromNow: TimeInterval(i * 30),        app: "Chrome")) }
        for i in 0..<3 { frames.append(frame(Int64(i + 10),  secondsFromNow: TimeInterval(90 + i * 30),  app: "Slack")) }
        // Burst 2.
        for i in 0..<3 { frames.append(frame(Int64(i + 100), secondsFromNow: TimeInterval(180 + i * 30), app: "Chrome")) }
        for i in 0..<3 { frames.append(frame(Int64(i + 110), secondsFromNow: TimeInterval(270 + i * 30), app: "Slack")) }
        // Burst 3.
        for i in 0..<3 { frames.append(frame(Int64(i + 200), secondsFromNow: TimeInterval(360 + i * 30), app: "Chrome")) }
        for i in 0..<3 { frames.append(frame(Int64(i + 210), secondsFromNow: TimeInterval(450 + i * 30), app: "Slack")) }

        let insights = InsightsEngine.candidates(from: frames)
        XCTAssertTrue(insights.contains { $0.kind == .workflowDetected },
                      "Expected at least one workflowDetected insight; got \(insights.map { $0.kind })")
    }

    func test_skipsLowSignalShortRun() {
        // 5 minutes of Chrome, no app switches, no big focus block, no
        // window-name pattern across sessions — should produce nothing.
        let frames = (0..<10).map { i in frame(Int64(i), secondsFromNow: TimeInterval(i * 30), app: "Chrome") }
        let insights = InsightsEngine.candidates(from: frames)
        XCTAssertTrue(insights.isEmpty, "Low-signal input should produce no candidates; got \(insights)")
    }

    // MARK: - Repeated file/window pattern

    func test_detectsRepeatedFileNamePattern() {
        // The same window_name ('shopify-product.csv — VS Code') appears in
        // 3+ separate time-clusters (gaps > 5 min between clusters).
        var frames: [FrameRow] = []
        let win = "shopify-product.csv — VS Code"
        // Cluster 1.
        for i in 0..<5 { frames.append(frame(Int64(i),       secondsFromNow: TimeInterval(i * 30),        app: "Code", window: win)) }
        // Gap > 5min.
        // Cluster 2.
        for i in 0..<5 { frames.append(frame(Int64(i + 100), secondsFromNow: TimeInterval(600 + i * 30),  app: "Code", window: win)) }
        // Cluster 3.
        for i in 0..<5 { frames.append(frame(Int64(i + 200), secondsFromNow: TimeInterval(1200 + i * 30), app: "Code", window: win)) }

        let insights = InsightsEngine.candidates(from: frames)
        XCTAssertTrue(insights.contains { $0.kind == .automationOpportunity },
                      "Expected at least one automationOpportunity; got \(insights.map { $0.kind })")
    }

    // MARK: - Focus block

    func test_detectsFocusBlock() {
        // 90 minutes of continuous VS Code (frames at 30s cadence, 5400s total).
        let frames = (0..<180).map { i in
            frame(Int64(i), secondsFromNow: TimeInterval(i * 30), app: "Code", window: "MemoryDB.swift — VS Code")
        }
        let insights = InsightsEngine.candidates(from: frames)
        XCTAssertTrue(insights.contains { $0.kind == .focusPattern },
                      "Expected a focusPattern insight; got \(insights.map { $0.kind })")
    }

    // MARK: - Ranking + cap

    func test_returnsAtMostFourInsights() {
        // Construct a busy day with many repeated pairs to overshoot the cap.
        var frames: [FrameRow] = []
        var id: Int64 = 0
        for burst in 0..<8 {
            let baseSeconds = burst * 300
            for app in ["Chrome", "Slack", "Code", "Notion", "Figma"] {
                for i in 0..<3 {
                    frames.append(frame(id, secondsFromNow: TimeInterval(baseSeconds + i * 15), app: app))
                    id += 1
                }
            }
        }
        let insights = InsightsEngine.candidates(from: frames)
        XCTAssertLessThanOrEqual(insights.count, 4)
    }

    func test_emptyInputReturnsEmpty() {
        XCTAssertEqual(InsightsEngine.candidates(from: []), [])
    }

    // MARK: - Pass 2 polish

    func test_polish_disabled_returnsCandidatesUnchanged() async {
        let original = sampleInsights()
        let polisher: InsightsEngine.Polisher = { _ in
            XCTFail("polisher should not be invoked when disabled")
            return []
        }
        let result = await InsightsEngine.polish(original, enabled: false, polisher: polisher)
        XCTAssertEqual(result, original)
    }

    func test_polish_enabled_appliesPolishedStrings() async {
        let original = sampleInsights()
        let polished = original.map { InsightsEngine.PolishedText(id: $0.id, title: "POLISHED \($0.kind.rawValue)", body: "polished body") }
        let polisher: InsightsEngine.Polisher = { _ in polished }
        let result = await InsightsEngine.polish(original, enabled: true, polisher: polisher)
        XCTAssertEqual(result.count, original.count)
        for (input, output) in zip(original, result) {
            XCTAssertEqual(output.id, input.id)
            XCTAssertEqual(output.kind, input.kind)
            XCTAssertEqual(output.cta, input.cta)
            XCTAssertTrue(output.title.hasPrefix("POLISHED "))
            XCTAssertEqual(output.body, "polished body")
        }
    }

    func test_polish_runtimeFailure_fallsBackToTemplated() async {
        let original = sampleInsights()
        let polisher: InsightsEngine.Polisher = { _ in throw StubError.boom }
        let result = await InsightsEngine.polish(original, enabled: true, polisher: polisher)
        XCTAssertEqual(result, original)
    }

    // MARK: - Cache

    func test_cache_writeReadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("insights-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = sampleInsights()
        InsightsEngine.saveCache(original, runtimeID: "claudeCode", aiPolished: false, to: url, now: Date())
        let loaded = InsightsEngine.loadCache(from: url, maxAge: 60, aiInsightsEnabled: false, now: Date())
        XCTAssertEqual(loaded, original)
    }

    func test_cache_expiredCacheReturnsNil() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("insights-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let writeTime = Date(timeIntervalSince1970: 1_000_000)
        InsightsEngine.saveCache(sampleInsights(), runtimeID: "claudeCode", aiPolished: false, to: url, now: writeTime)
        // Read time 700s later; maxAge = 600s → expired.
        let readTime = writeTime.addingTimeInterval(700)
        let loaded = InsightsEngine.loadCache(from: url, maxAge: 600, aiInsightsEnabled: false, now: readTime)
        XCTAssertNil(loaded)
    }

    func test_cache_invalidatedWhenAIToggleChanges() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("insights-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        // Write with AI-polished cache.
        InsightsEngine.saveCache(sampleInsights(), runtimeID: "claudeCode", aiPolished: true, to: url, now: Date())
        // User has since toggled AI off → cache should be invalidated.
        let loaded = InsightsEngine.loadCache(from: url, maxAge: 600, aiInsightsEnabled: false, now: Date())
        XCTAssertNil(loaded, "Cache written with AI-polished content should not be served when the toggle is off")
        // Symmetric case: cache written without AI; user toggled AI on.
        InsightsEngine.saveCache(sampleInsights(), runtimeID: "claudeCode", aiPolished: false, to: url, now: Date())
        let loaded2 = InsightsEngine.loadCache(from: url, maxAge: 600, aiInsightsEnabled: true, now: Date())
        XCTAssertNil(loaded2, "Cache written without AI polish should not be served when the toggle is on")
    }

    // MARK: -

    private func sampleInsights() -> [Insight] {
        [
            Insight(id: UUID(), kind: .workflowDetected,      title: "WD",  body: "wd body", cta: .createFlow(seed: "x"),       signal: 5),
            Insight(id: UUID(), kind: .automationOpportunity, title: "AO",  body: "ao body", cta: .createSkill(seed: "y"),      signal: 4),
            Insight(id: UUID(), kind: .focusPattern,          title: "FP",  body: "fp body", cta: .viewMemory(startedAt: now, endedAt: now), signal: 3),
        ]
    }
}

private enum StubError: Error { case boom }
