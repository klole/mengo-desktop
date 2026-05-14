import Foundation

/// Plain value types the Memory Dashboard's data layer trades in. No I/O, no
/// formatting — `MemoryDB` produces the raw shapes here and the pure services
/// (`SessionsService`, `AppUsageService`) layer display logic on top.

/// One screen frame row, the unit the recorder writes per visible capture.
struct FrameRow: Equatable, Sendable {
    let id: Int64
    let timestamp: Date
    let appName: String
    let windowName: String?
    let browserURL: String?
}

/// Raw app frame count over a window — `AppUsageService.rows(from:)` enriches
/// with `displayName`, `iconName`, and `sharePercent`.
struct RawAppCount: Equatable, Sendable {
    let appName: String
    let frameCount: Int
}

/// Display-ready app usage row for the Top Applications card.
struct AppUsageRow: Equatable, Sendable, Identifiable {
    let appName: String       // raw name from the DB — the stable id
    let displayName: String   // humanized
    let iconName: String      // SF Symbol
    let frameCount: Int
    let sharePercent: Int     // 0...100, rounded
    var id: String { appName }
}

/// Display-ready row for the Recent Sessions card. A "session" is a
/// contiguous time-cluster of frames (gap < 5 min); within the cluster,
/// one app dominates and labels the session.
struct SessionRow: Equatable, Sendable, Identifiable {
    let id: UUID
    let title: String         // "Chrome session" / "VS Code session"
    let subtitle: String?     // dominant window_name OR "with <secondApp>"
    let startedAt: Date
    let endedAt: Date
    let frameCount: Int
    let appIcons: [String]    // top 3 SF Symbol names by frame count
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
}

/// Live-feed event. IDs partition by kind so screenshots and transcriptions
/// don't collide; the cursor in `MemoryDB.recentActivity` tracks them
/// separately.
enum ActivityEvent: Equatable, Sendable, Identifiable {
    case screenshot(id: Int64, at: Date, appName: String, windowName: String?)
    case transcription(id: Int64, at: Date, snippet: String)
    case urlVisited(id: Int64, at: Date, url: String, appName: String)

    var id: String {
        switch self {
        case .screenshot(let id, _, _, _): return "screenshot-\(id)"
        case .transcription(let id, _, _): return "transcription-\(id)"
        case .urlVisited(let id, _, _, _): return "url-\(id)"
        }
    }

    var timestamp: Date {
        switch self {
        case .screenshot(_, let t, _, _), .transcription(_, let t, _), .urlVisited(_, let t, _, _):
            return t
        }
    }
}

/// Capture mode for the recorder. Drives the `--fps` flag handed to the
/// recorder process on start; persisted in `SettingsStore.captureMode`. The
/// numbers below are conservative defaults — tune once we've validated them
/// against the bundled recorder build.
enum CaptureMode: String, CaseIterable, Sendable, Codable {
    case smartCapture   // change-detected captures, low constant cost
    case allChanges     // capture every change at a higher rate
    case periodic       // slow steady cadence

    var displayName: String {
        switch self {
        case .smartCapture: return "Smart Capture"
        case .allChanges:   return "Changes only"
        case .periodic:     return "Periodic"
        }
    }

    var caption: String {
        switch self {
        case .smartCapture: return "1 fps, change-detected (default)"
        case .allChanges:   return "2 fps, every visible change"
        case .periodic:     return "0.5 fps, steady cadence"
        }
    }

    /// CLI flags appended to the recorder invocation for this mode.
    var recorderFlags: [String] {
        switch self {
        case .smartCapture: return ["--fps", "1.0"]
        case .allChanges:   return ["--fps", "2.0"]
        case .periodic:     return ["--fps", "0.5"]
        }
    }
}

// MARK: - Recording schedule

/// Day-of-week used by `RecordingScheduleRule.recurring`. Aligned with
/// `Calendar`'s 1-based weekday component (1 = Sunday).
enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sun = 1, mon, tue, wed, thu, fri, sat

    var shortName: String {
        switch self {
        case .sun: return "Sun"; case .mon: return "Mon"; case .tue: return "Tue"
        case .wed: return "Wed"; case .thu: return "Thu"; case .fri: return "Fri"
        case .sat: return "Sat"
        }
    }
}

/// Time-of-day with minute resolution. `ClockTime(hour: 9, minute: 0)` is 9 am
/// in the user's current time zone — schedules are evaluated against the
/// system calendar at runtime.
struct ClockTime: Equatable, Codable, Sendable {
    let hour: Int    // 0..23
    let minute: Int  // 0..59

    var minutesSinceMidnight: Int { hour * 60 + minute }

    func formatted() -> String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// One rule in a `RecordingSchedule`. Recurring rules fire on the listed
/// weekdays, between start and end (inclusive of start, exclusive of end).
/// One-off rules fire once over an absolute date range.
enum RecordingScheduleRule: Equatable, Codable, Sendable, Identifiable {
    case recurring(id: UUID, days: Set<Weekday>, start: ClockTime, end: ClockTime)
    case oneOff(id: UUID, start: Date, end: Date)

    var id: UUID {
        switch self {
        case .recurring(let id, _, _, _): return id
        case .oneOff(let id, _, _):       return id
        }
    }

    /// True when `date` falls inside the rule's window.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .recurring(_, let days, let start, let end):
            let comps = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            guard let wd = comps.weekday, let h = comps.hour, let m = comps.minute,
                  let weekday = Weekday(rawValue: wd) else { return false }
            guard days.contains(weekday) else { return false }
            let now = h * 60 + m
            let s = start.minutesSinceMidnight
            let e = end.minutesSinceMidnight
            if s <= e { return now >= s && now < e }
            // Wraps midnight (e.g. 22:00 → 06:00).
            return now >= s || now < e
        case .oneOff(_, let start, let end):
            return date >= start && date < end
        }
    }
}

/// The user's saved recording schedule. `nil` (or empty `rules`) means the
/// recorder is governed manually; otherwise the controller follows the rules
/// on each health-poll tick.
struct RecordingSchedule: Equatable, Codable, Sendable {
    var rules: [RecordingScheduleRule]

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        rules.contains { $0.contains(date, calendar: calendar) }
    }

    static let empty = RecordingSchedule(rules: [])
}

/// Selector for `MemoryDashboardStore.topAppsWindow`. Stored in `SettingsStore`
/// so the last choice survives launches.
enum TopAppsWindow: String, CaseIterable, Sendable, Codable {
    case today, last7Days, last30Days

    var seconds: TimeInterval {
        switch self {
        case .today: return 24 * 60 * 60
        case .last7Days: return 7 * 24 * 60 * 60
        case .last30Days: return 30 * 24 * 60 * 60
        }
    }

    var displayName: String {
        switch self {
        case .today: return "Today"
        case .last7Days: return "Last 7 days"
        case .last30Days: return "Last 30 days"
        }
    }
}
