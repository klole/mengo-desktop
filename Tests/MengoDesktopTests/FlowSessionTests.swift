import XCTest
@testable import MengoDesktop

final class FlowSessionTests: XCTestCase {

    func testProactiveSessionTimeRangeMatchesActiveStart() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var s = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: start, endTime: nil)
        s.endTime = start.addingTimeInterval(45)
        XCTAssertEqual(s.timeRangeStart, start)
        XCTAssertEqual(s.timeRangeEnd, start.addingTimeInterval(45))
        XCTAssertEqual(s.durationSeconds, 45, accuracy: 0.01)
    }

    func testRetroactiveTimeRangeUsesBufferStart() {
        let bufferStart = Date(timeIntervalSince1970: 1_700_000_000)
        let activeStart = bufferStart.addingTimeInterval(300)
        var s = FlowSession(mode: .retroactive, bufferRangeStart: bufferStart, activeRecordingStart: activeStart, endTime: nil)
        s.endTime = activeStart.addingTimeInterval(60)
        XCTAssertEqual(s.timeRangeStart, bufferStart)
        XCTAssertEqual(s.timeRangeEnd, activeStart.addingTimeInterval(60))
        XCTAssertEqual(s.durationSeconds, 360, accuracy: 0.01)
    }
}
