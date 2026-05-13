import XCTest
@testable import MengoDesktop

final class RecorderProcessTests: XCTestCase {

    func test_newToken_isSpPrefixedEightHex() {
        let token = RecorderProcess.newToken()
        XCTAssertNotNil(token.range(of: #"^sp-[0-9a-f]{8}$"#, options: .regularExpression),
                        "unexpected token: \(token)")
    }

    func test_newToken_isDifferentEachCall() {
        XCTAssertNotEqual(RecorderProcess.newToken(), RecorderProcess.newToken())
    }
}
