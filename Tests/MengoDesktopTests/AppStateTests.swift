import XCTest
@testable import MengoDesktop

@MainActor
final class AppStateTests: XCTestCase {

    func test_freshState_opensOnMemory() {
        XCTAssertEqual(AppState().selectedSection, .memory)
    }

    func test_selectedSection_isMutable() {
        let state = AppState()
        state.selectedSection = .studio
        XCTAssertEqual(state.selectedSection, .studio)
    }
}
