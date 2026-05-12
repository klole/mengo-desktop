import XCTest
@testable import ScreenpipeFlow

final class ScreenpipeClientTests: XCTestCase {

    func testHealthParsesRunningAudio() throws {
        let payload = """
        {
          "status": "healthy",
          "frame_status": "ok",
          "audio_status": "ok",
          "ui_status": "ok",
          "last_frame_timestamp": "2026-05-12T14:30:00Z"
        }
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertTrue(health.isHealthy)
        XCTAssertEqual(health.audioStatus, .running)
    }

    func testHealthParsesPausedAudio() throws {
        let payload = """
        {"status":"healthy","frame_status":"ok","audio_status":"paused","ui_status":"ok"}
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertEqual(health.audioStatus, .paused)
    }

    func testHealthParsesUnknownAudioStatus() throws {
        let payload = """
        {"status":"healthy","frame_status":"ok","audio_status":"weird_value","ui_status":"ok"}
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertEqual(health.audioStatus, .unknown)
    }

    func testHealthParsesUnhealthy() throws {
        let payload = """
        {"status":"error","frame_status":"err","audio_status":"err","ui_status":"err"}
        """.data(using: .utf8)!
        let health = try ScreenpipeClient.parseHealth(payload)
        XCTAssertFalse(health.isHealthy)
    }

    func testThumbnailIndexRequiresToken() async {
        // /search requires Authorization: Bearer; the client must refuse to even
        // make the request when no token is configured (rather than silently 403ing).
        let client = ScreenpipeClient(token: nil)
        do {
            _ = try await client.thumbnailIndex(from: Date().addingTimeInterval(-60),
                                                to: Date())
            XCTFail("expected unauthorized error")
        } catch ScreenpipeClient.ClientError.unauthorized {
            // expected
        } catch {
            XCTFail("expected .unauthorized, got \(error)")
        }
    }

    func testParseISO8601HandlesMixedFormats() {
        XCTAssertNotNil(ScreenpipeClient.parseISO8601("2026-05-12T14:25:00Z"))
        XCTAssertNotNil(ScreenpipeClient.parseISO8601("2026-05-12T15:04:37-06:00"))
        XCTAssertNotNil(ScreenpipeClient.parseISO8601("2026-05-12T15:04:37.623838-06:00"))
        XCTAssertNotNil(ScreenpipeClient.parseISO8601("2026-05-12T15:04:37.623Z"))
        XCTAssertNil(ScreenpipeClient.parseISO8601("not a date"))
    }

    func testHealthRejectsNonJSON() {
        let payload = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try ScreenpipeClient.parseHealth(payload))
    }

    func testThumbnailIndexParsesOCRResults() throws {
        let payload = """
        {
          "data": [
            {"type":"OCR","content":{"timestamp":"2026-05-12T14:25:00Z","app_name":"Google Chrome","window_name":"Dashboard"}},
            {"type":"OCR","content":{"timestamp":"2026-05-12T14:27:00Z","app_name":"Slack","window_name":"#growth"}},
            {"type":"OCR","content":{"timestamp":"2026-05-12T14:29:00Z","app_name":"Slack","window_name":"#growth"}}
          ]
        }
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].appName, "Google Chrome")
        XCTAssertEqual(items[1].appName, "Slack")
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        XCTAssertEqual(items[0].timestamp, iso.date(from: "2026-05-12T14:25:00Z"))
    }

    func testThumbnailIndexHandlesEmptyResults() throws {
        let payload = """
        {"data":[]}
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items, [])
    }

    func testThumbnailIndexSkipsNonOCREntries() throws {
        let payload = """
        {"data":[
          {"type":"OCR","content":{"timestamp":"2026-05-12T14:25:00Z","app_name":"Chrome","window_name":""}},
          {"type":"Audio","content":{"timestamp":"2026-05-12T14:26:00Z","transcription":"hi"}}
        ]}
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items.count, 1)
    }

    func testThumbnailIndexParsesFractionalSecondsAndTZOffset() throws {
        // Real screenpipe output: ISO8601 with both microsecond fractional
        // seconds AND timezone offset (e.g. -06:00). Earlier impl using only
        // .withInternetDateTime silently dropped these.
        let payload = """
        {"data":[
          {"type":"OCR","content":{"timestamp":"2026-05-12T15:04:37.623838-06:00","app_name":"Claude","window_name":""}},
          {"type":"OCR","content":{"timestamp":"2026-05-12T22:00:00.000Z","app_name":"Slack","window_name":""}}
        ]}
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items.count, 2, "fractional-second timestamps must parse")
        // 15:04:37-06:00 = 21:04:37Z (earlier) → Claude first
        // 22:00:00Z (later) → Slack second
        XCTAssertEqual(items[0].appName, "Claude")
        XCTAssertEqual(items[1].appName, "Slack")
    }

    func testThumbnailIndexSortsByTimestampAscending() throws {
        let payload = """
        {"data":[
          {"type":"OCR","content":{"timestamp":"2026-05-12T14:29:00Z","app_name":"A","window_name":""}},
          {"type":"OCR","content":{"timestamp":"2026-05-12T14:25:00Z","app_name":"B","window_name":""}},
          {"type":"OCR","content":{"timestamp":"2026-05-12T14:27:00Z","app_name":"C","window_name":""}}
        ]}
        """.data(using: .utf8)!
        let items = try ScreenpipeClient.parseThumbnailIndex(payload)
        XCTAssertEqual(items.map { $0.appName }, ["B", "C", "A"])
    }
}
