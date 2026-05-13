import XCTest
@testable import MengoDesktop

final class MengoURLTests: XCTestCase {
    func test_parsesAuthLink() {
        XCTAssertEqual(MengoURL.parse(URL(string: "mengo://auth?token=abc123")!), .auth(token: "abc123"))
    }
    func test_parsesRefreshLink() {
        XCTAssertEqual(MengoURL.parse(URL(string: "mengo://refresh")!), .refresh)
    }
    func test_rejectsBadLinks() {
        XCTAssertNil(MengoURL.parse(URL(string: "mengo://auth")!))            // no token
        XCTAssertNil(MengoURL.parse(URL(string: "mengo://something")!))
        XCTAssertNil(MengoURL.parse(URL(string: "https://mengo.ai/auth?token=x")!))
    }
}
