import XCTest
@testable import MengoDesktop

final class APIClientTests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func test_screenpipeHealth_decodesCoreFields_ignoringExtras() throws {
        let data = try loadFixture("health-ok.json")
        let health = try JSONDecoder().decode(ScreenpipeHealth.self, from: data)
        XCTAssertEqual(health.status, "healthy")
        XCTAssertEqual(health.frameStatus, "ok")
        XCTAssertEqual(health.audioStatus, "ok")
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
