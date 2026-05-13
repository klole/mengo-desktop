import XCTest
@testable import MengoDesktop

@MainActor
final class HotkeyManagerTests: XCTestCase {
    func test_init_andRegister_doNotCrash() {
        let m = HotkeyManager()
        var fired = false
        m.register(HotkeyManager.recordToggle) { fired = true }
        XCTAssertFalse(fired)   // registering doesn't fire the action
    }
}
