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
