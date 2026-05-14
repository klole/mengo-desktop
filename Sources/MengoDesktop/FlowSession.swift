import Foundation

/// How a Flow recording was started. Mode C ("grab last N minutes" — `.retroactive`)
/// is Phase 3b; in 3a a session is always `.proactive` with `bufferRangeStart == nil`.
/// The field set is kept identical to V1's `RecordingSession` so 3b is a drop-in.
enum RecordingMode: String, Codable, Equatable {
    case proactive
    case retroactive
}

/// The time range Flow bookkeeps between Start and Stop. The recorder (owned by
/// Mengo Memory) does the actual capturing; this is just a span to hand the
/// synthesizer.
struct FlowSession: Equatable {
    let mode: RecordingMode
    /// Mode `.retroactive` only — earliest point grabbed from the recorder's buffer.
    let bufferRangeStart: Date?
    /// When the user started narrating forward (clicked Start / Begin From Here).
    let activeRecordingStart: Date
    /// Set when the user clicks Stop. `nil` while still recording.
    var endTime: Date?

    /// Full time range to feed the synthesizer.
    var timeRangeStart: Date { bufferRangeStart ?? activeRecordingStart }
    var timeRangeEnd: Date { endTime ?? Date() }
    var durationSeconds: TimeInterval { timeRangeEnd.timeIntervalSince(timeRangeStart) }
}
