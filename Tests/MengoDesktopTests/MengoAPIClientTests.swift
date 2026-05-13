import XCTest
@testable import MengoDesktop

final class MengoAPIClientTests: XCTestCase {
    func test_decodesExchangeResponse_free() throws {
        let data = Data(#"{"sessionToken":"sess_abc","account":{"email":"a@b.com","plan":"free","flowLimit":3}}"#.utf8)
        let r = try MengoAPIClient.decodeExchange(data)
        XCTAssertEqual(r.sessionToken, "sess_abc")
        XCTAssertEqual(r.account.email, "a@b.com")
        XCTAssertEqual(r.account.plan, .free)
        XCTAssertEqual(r.account.flowLimit, 3)
    }
    func test_decodesAccount_proHasNilLimit() throws {
        let acct = try MengoAPIClient.decodeAccount(Data(#"{"email":"p@b.com","plan":"pro","flowLimit":null}"#.utf8))
        XCTAssertEqual(acct.plan, .pro)
        XCTAssertNil(acct.flowLimit)
    }
    func test_decodesAccount_missingFlowLimitTreatedAsNil() throws {
        let acct = try MengoAPIClient.decodeAccount(Data(#"{"email":"p@b.com","plan":"pro"}"#.utf8))
        XCTAssertNil(acct.flowLimit)
    }
}
