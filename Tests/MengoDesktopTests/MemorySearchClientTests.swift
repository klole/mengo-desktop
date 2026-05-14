import XCTest
@testable import MengoDesktop

final class MemorySearchClientTests: XCTestCase {

    func test_parseMomentIndex_decodesOCRRows_skipsOthers_tolerantTimestamps() {
        let json = Data("""
        { "data": [
          { "type": "OCR", "content": { "timestamp": "2026-05-12T14:25:00.123Z", "app_name": "Google Chrome", "window_name": "Staging Admin" } },
          { "type": "OCR", "content": { "timestamp": "2026-05-12T14:27:00Z", "app_name": "Slack", "window_name": "#growth" } },
          { "type": "Audio", "content": { "timestamp": "2026-05-12T14:26:00Z", "transcription": "blah" } },
          { "type": "OCR", "content": { "timestamp": "2026-05-12T14:30:00Z" } }
        ] }
        """.utf8)
        let moments = MemorySearchClient.parseMomentIndex(json)
        XCTAssertEqual(moments.count, 3)                          // the Audio row is skipped
        XCTAssertEqual(moments.first?.appName, "Google Chrome")   // sorted oldest-first
        XCTAssertEqual(moments.first?.windowName, "Staging Admin")
        XCTAssertEqual(moments[1].appName, "Slack")
        XCTAssertEqual(moments[2].appName, "")                    // missing app_name → ""
        XCTAssertEqual(moments[2].windowName, "")
        XCTAssertTrue(moments[0].timestamp < moments[1].timestamp)
        XCTAssertTrue(moments[1].timestamp < moments[2].timestamp)
    }

    func test_parseMomentIndex_malformed_returnsEmpty() {
        XCTAssertTrue(MemorySearchClient.parseMomentIndex(Data("nope".utf8)).isEmpty)
        XCTAssertTrue(MemorySearchClient.parseMomentIndex(Data(#"{"ok":true}"#.utf8)).isEmpty)
    }

    func test_decimate_keepsRoughlyOnePerInterval() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let moments = (0..<10).map { i in
            Moment(timestamp: base.addingTimeInterval(Double(i) * 5), appName: "App", windowName: "w\(i)")  // every 5 s
        }
        let kept = MemorySearchClient.decimate(moments, minIntervalSec: 15)
        XCTAssertEqual(kept.map(\.windowName), ["w0", "w3", "w6", "w9"])  // 0s, 15s, 30s, 45s
    }
}
