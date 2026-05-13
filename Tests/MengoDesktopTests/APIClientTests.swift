import XCTest
@testable import MengoDesktop

final class APIClientTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func test_screenpipeHealth_decodesCoreAndRichFields() throws {
        let data = try loadFixture("health-ok.json")
        let h = try JSONDecoder().decode(ScreenpipeHealth.self, from: data)
        XCTAssertEqual(h.status, "healthy")
        XCTAssertEqual(h.frameStatus, "ok")
        XCTAssertEqual(h.audioStatus, "ok")
        XCTAssertEqual(h.version, "0.3.327")
        XCTAssertEqual(h.monitors, ["Display 1 (1728x1117)", "Display 2 (3440x1440)"])
        XCTAssertEqual(h.pipeline?.framesCaptured, 53)
        XCTAssertEqual(h.pipeline?.uptimeSecs.map { Int($0) }, 257)
        XCTAssertEqual(h.audioPipeline?.totalWords, 225)
        XCTAssertEqual(h.audioPipeline?.audioDevices, ["R-Phonak hearing aid (input)", "System Audio (output)"])
        XCTAssertEqual(h.lastFrameTimestamp, "2026-05-12T18:31:18-06:00")
    }

    func test_screenpipeHealth_decodesFromMinimalBody() throws {
        let data = Data(#"{"status":"healthy","frame_status":"ok","audio_status":"degraded"}"#.utf8)
        let health = try JSONDecoder().decode(ScreenpipeHealth.self, from: data)
        XCTAssertEqual(health.audioStatus, "degraded")
    }

    func test_apiClient_baseURLIsLocalScreenpipe() async {
        let client = APIClient(token: "sp-deadbeef")
        let base = await client.baseURLForTesting.absoluteString
        XCTAssertEqual(base, "http://127.0.0.1:3030")
    }
}
