import XCTest
@testable import MengoDesktop

private enum StubError: Error { case boom }

private actor StubActivitySource: ActivityFeedSource {
    private var responses: [Result<[ActivityEvent], Error>] = []
    private(set) var callHistory: [(sinceFrameID: Int64, sinceAudioID: Int64)] = []
    private var callIndex = 0

    func setResponses(_ rs: [Result<[ActivityEvent], Error>]) { responses = rs }

    func recentActivity(sinceFrameID: Int64, sinceAudioID: Int64, limit: Int) async throws -> [ActivityEvent] {
        callHistory.append((sinceFrameID, sinceAudioID))
        defer { callIndex += 1 }
        guard callIndex < responses.count else { return [] }
        switch responses[callIndex] {
        case .success(let evts): return evts
        case .failure(let err):  throw err
        }
    }

    func lastFrameID() async throws -> Int64? { 0 }
    func lastAudioID() async throws -> Int64? { 0 }
}

final class ActivityFeedStreamTests: XCTestCase {

    func test_emitsOnlyNonEmptyBatchesInOrder() async throws {
        let stub = StubActivitySource()
        let e1: ActivityEvent = .screenshot(id: 1, at: Date(), appName: "Chrome", windowName: nil)
        let e2: ActivityEvent = .screenshot(id: 2, at: Date(), appName: "Code", windowName: nil)
        await stub.setResponses([
            .success([e1]),
            .success([]),        // empty — should NOT yield
            .success([e2]),
        ])

        let stream = ActivityFeedStream(source: stub, interval: .milliseconds(5), backoff: .milliseconds(5))
        var iter = stream.events().makeAsyncIterator()

        let b1 = try await iter.next()
        XCTAssertEqual(b1?.count, 1)
        XCTAssertEqual(b1?.first?.id, "screenshot-1")

        let b2 = try await iter.next()
        XCTAssertEqual(b2?.count, 1)
        XCTAssertEqual(b2?.first?.id, "screenshot-2")
    }

    func test_recoversAfterError() async throws {
        let stub = StubActivitySource()
        let e1: ActivityEvent = .screenshot(id: 1, at: Date(), appName: "Chrome", windowName: nil)
        let e2: ActivityEvent = .screenshot(id: 2, at: Date(), appName: "Code", windowName: nil)
        await stub.setResponses([
            .success([e1]),
            .failure(StubError.boom),
            .success([e2]),
        ])

        let stream = ActivityFeedStream(source: stub, interval: .milliseconds(5), backoff: .milliseconds(5))
        var iter = stream.events().makeAsyncIterator()

        let b1 = try await iter.next()
        XCTAssertEqual(b1?.first?.id, "screenshot-1")

        // The stream swallows the error and keeps polling — the next yield is from tick 3.
        let b2 = try await iter.next()
        XCTAssertEqual(b2?.first?.id, "screenshot-2")
    }

    func test_advancesCursorToMaxIDPerBatch() async throws {
        let stub = StubActivitySource()
        let frame3: ActivityEvent = .screenshot(id: 3, at: Date(), appName: "Chrome", windowName: nil)
        let frame7: ActivityEvent = .screenshot(id: 7, at: Date(), appName: "Code", windowName: nil)
        let audio5: ActivityEvent = .transcription(id: 5, at: Date(), snippet: "hi")
        await stub.setResponses([
            .success([frame7, frame3, audio5]),  // newest-first (id 7), audio at 5
            .success([]),
            .success([]),
        ])

        let stream = ActivityFeedStream(source: stub, interval: .milliseconds(5), backoff: .milliseconds(5))
        var iter = stream.events().makeAsyncIterator()
        _ = try await iter.next()
        // Give the loop a tick to advance the cursor and make the next call.
        try await Task.sleep(for: .milliseconds(20))

        let history = await stub.callHistory
        XCTAssertGreaterThanOrEqual(history.count, 2)
        // Tick 1 started at 0/0.
        XCTAssertEqual(history[0].sinceFrameID, 0)
        XCTAssertEqual(history[0].sinceAudioID, 0)
        // Tick 2 must have advanced to max(frame ids) = 7 and max(audio ids) = 5.
        XCTAssertEqual(history[1].sinceFrameID, 7)
        XCTAssertEqual(history[1].sinceAudioID, 5)
    }
}
