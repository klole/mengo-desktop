import Foundation

enum RecordingMode: String, Codable, Equatable {
    case proactive
    case retroactive
}

struct RecordingSession: Equatable {
    let mode: RecordingMode
    /// Mode .retroactive only — earliest point grabbed from screenpipe's buffer.
    let bufferRangeStart: Date?
    /// When the user started narrating forward (clicked Start or Begin From Here).
    let activeRecordingStart: Date
    /// Set when the user clicks Stop. nil while still recording.
    var endTime: Date?

    /// Full time range to feed to the synthesizer.
    var timeRangeStart: Date {
        bufferRangeStart ?? activeRecordingStart
    }

    var timeRangeEnd: Date {
        endTime ?? Date()
    }

    var durationSeconds: TimeInterval {
        timeRangeEnd.timeIntervalSince(timeRangeStart)
    }
}

struct FlowEntry: Equatable, Identifiable {
    let slug: String
    let name: String
    let path: URL
    let createdAt: Date

    var id: String { slug }
}
