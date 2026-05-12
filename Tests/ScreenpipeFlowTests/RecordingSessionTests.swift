import XCTest
@testable import ScreenpipeFlow

final class RecordingSessionTests: XCTestCase {

    func testProactiveSessionTimeRangeMatchesActiveStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var s = RecordingSession(mode: .proactive,
                                 bufferRangeStart: nil,
                                 activeRecordingStart: start)
        s.endTime = start.addingTimeInterval(45)
        XCTAssertEqual(s.timeRangeStart, start)
        XCTAssertEqual(s.timeRangeEnd, start.addingTimeInterval(45))
        XCTAssertEqual(s.durationSeconds, 45, accuracy: 0.01)
    }

    func testRetroactiveTimeRangeUsesBufferStart() {
        let bufferStart = Date(timeIntervalSince1970: 1_700_000_000)
        let activeStart = bufferStart.addingTimeInterval(300) // 5 min later
        var s = RecordingSession(mode: .retroactive,
                                 bufferRangeStart: bufferStart,
                                 activeRecordingStart: activeStart)
        s.endTime = activeStart.addingTimeInterval(60)
        XCTAssertEqual(s.timeRangeStart, bufferStart)
        XCTAssertEqual(s.timeRangeEnd, activeStart.addingTimeInterval(60))
        XCTAssertEqual(s.durationSeconds, 360, accuracy: 0.01)
    }

    func testFlowEntryEquality() {
        let url = URL(fileURLWithPath: "/tmp/foo")
        let date = Date()
        let a = FlowEntry(slug: "x", name: "X", path: url, createdAt: date)
        let b = FlowEntry(slug: "x", name: "X", path: url, createdAt: date)
        XCTAssertEqual(a, b)
    }
}
