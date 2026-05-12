import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case error(String)
    }

    private(set) var sessionState: SessionState = .idle
}
