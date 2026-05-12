import XCTest
@testable import ScreenpipeFlow

@MainActor
final class AppStateTests: XCTestCase {

    func testInitialStateIsIdle() {
        let state = AppState()
        if case .idle = state.sessionState { return }
        XCTFail("expected .idle, got \(state.sessionState)")
    }
}
