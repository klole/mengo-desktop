import Foundation

/// The recorder's user-facing state. Mirrors V1's `ScreenpipeMenu/AppState.Status`
/// (renamed `vision`→`screen` to match the UI wording).
enum RecorderStatus: Equatable {
    case idle
    case starting
    case recording
    case audioPaused
    case screenPaused
    case bothPaused
    case error(String)

    /// True while screenpipe is meant to be running (recording or partially paused).
    var isRecording: Bool {
        switch self {
        case .recording, .audioPaused, .screenPaused, .bothPaused: return true
        case .idle, .starting, .error: return false
        }
    }

    /// Combine the two pause axes into a single status. Only valid while running —
    /// callers in `.idle` / `.starting` / `.error` don't use this.
    static func from(audioPaused: Bool, screenPaused: Bool) -> RecorderStatus {
        switch (audioPaused, screenPaused) {
        case (false, false): return .recording
        case (true,  false): return .audioPaused
        case (false, true):  return .screenPaused
        case (true,  true):  return .bothPaused
        }
    }
}
