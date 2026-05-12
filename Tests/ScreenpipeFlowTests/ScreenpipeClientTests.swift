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

    func testHealthRejectsNonJSON() {
        let payload = "not json".data(using: .utf8)!
        XCTAssertThrowsError(try ScreenpipeClient.parseHealth(payload))
    }
}
