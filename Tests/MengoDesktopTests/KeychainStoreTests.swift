import XCTest
@testable import MengoDesktop

final class KeychainStoreTests: XCTestCase {
    func test_inMemorySecretStore_roundTrips() {
        let s = InMemorySecretStore()
        XCTAssertNil(s.get("k"))
        s.set("v1", for: "k")
        XCTAssertEqual(s.get("k"), "v1")
        s.set("v2", for: "k")
        XCTAssertEqual(s.get("k"), "v2")
        s.delete("k")
        XCTAssertNil(s.get("k"))
    }
}
