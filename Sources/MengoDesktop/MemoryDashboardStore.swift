import Foundation
import Observation

/// Slice of `MemoryDB` the dashboard store consumes. Declared as a protocol so
/// the store can be tested without a real SQLite file. `MemoryDB` conforms via
/// its existing methods.
protocol MemoryDashboardSource: ActivityFeedSource {
    func topApps(window: TimeInterval, limit: Int) async throws -> [RawAppCount]
    func recentFrames(window: TimeInterval, limit: Int) async throws -> [FrameRow]
}

extension MemoryDB: MemoryDashboardSource {}

/// Owns the displayable state for `MemoryDashboardPane`. Refreshes the data
/// derived from the recorder DB on demand (and, in Part B+, on a 60-s timer).
///
/// Part A — what's here today:
///   - `topApps`            populated from `db.topApps`
///   - `recentSessions`     populated from `db.recentFrames` + SessionsService
///   - `recentActivity`     placeholder; the activity-stream consumer lands in B4
///   - `insights`           placeholder; populated by `InsightsEngine` in D1
@Observable
@MainActor
final class MemoryDashboardStore {

    private(set) var topApps: [AppUsageRow] = []
    private(set) var recentSessions: [SessionRow] = []
    private(set) var recentActivity: [ActivityEvent] = []
    private(set) var insights: [String] = []   // typed in D1; placeholder for now

    var topAppsWindow: TopAppsWindow {
        didSet { settings.topAppsWindow = topAppsWindow }
    }

    @ObservationIgnored private let db: MemoryDashboardSource
    @ObservationIgnored private let settings: SettingsStore

    init(db: MemoryDashboardSource, settings: SettingsStore) {
        self.db = db
        self.settings = settings
        self.topAppsWindow = settings.topAppsWindow
    }

    /// Re-pulls `topApps` and `recentSessions` from the DB using the current
    /// `topAppsWindow`. Sessions always look at the last 24 h regardless of
    /// the picker (the picker is a Top Apps concept).
    func refresh() async {
        async let topAppsTask = loadTopApps()
        async let sessionsTask = loadSessions()
        let (apps, sessions) = await (topAppsTask, sessionsTask)
        self.topApps = apps
        self.recentSessions = sessions
    }

    /// Updates the persisted window selection and re-runs the Top Apps query.
    func setTopAppsWindow(_ window: TopAppsWindow) async {
        self.topAppsWindow = window
        self.topApps = await loadTopApps()
    }

    // MARK: -

    private func loadTopApps() async -> [AppUsageRow] {
        do {
            let raw = try await db.topApps(window: topAppsWindow.seconds, limit: 7)
            return AppUsageService.rows(from: raw)
        } catch {
            return []
        }
    }

    private func loadSessions() async -> [SessionRow] {
        do {
            let frames = try await db.recentFrames(window: 24 * 60 * 60, limit: 1000)
            return SessionsService.cluster(frames)
        } catch {
            return []
        }
    }
}
