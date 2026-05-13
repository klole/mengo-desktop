import Foundation

/// The Flow product's state machine. Mode C ("grab last N min") is Phase 3b;
/// in 3a `recording` is always proactive (`session.bufferRangeStart == nil`).
enum FlowState: Equatable {
    case idle
    case recording(FlowSession)
    case synthesizing(URL)   // manifest path
    case reviewing(URL)      // skill directory
    case error(String)
}
