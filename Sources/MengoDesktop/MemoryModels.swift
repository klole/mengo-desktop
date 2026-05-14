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
