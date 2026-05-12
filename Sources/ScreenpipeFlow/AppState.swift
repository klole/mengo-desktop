import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum SessionState: Equatable {
        case idle
        case browsingTimeline
        case recording(RecordingSession)
        case synthesizing(URL)        // manifest path
        case reviewing(URL)           // skill directory path
        case error(String)
    }

    private(set) var sessionState: SessionState = .idle
    private(set) var library: [FlowEntry] = []
}
