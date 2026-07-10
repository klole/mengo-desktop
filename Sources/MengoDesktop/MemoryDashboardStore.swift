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

/// Owns the displayable state for `MemoryDashboardPane`. Refreshes recorder
/// summaries on a 60-second timer and consumes the live activity stream.
@Observable
@MainActor
final class MemoryDashboardStore {

    private(set) var topApps: [AppUsageRow] = []
    private(set) var recentSessions: [SessionRow] = []
    private(set) var recentActivity: [ActivityEvent] = []
    private(set) var insights: [Insight] = []

    var topAppsWindow: TopAppsWindow {
        didSet { settings.topAppsWindow = topAppsWindow }
    }

    @ObservationIgnored private let db: MemoryDashboardSource
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let activityStream: ActivityFeedStream
    @ObservationIgnored private let insightsPolisher: InsightsEngine.Polisher

    init(
        db: MemoryDashboardSource,
        settings: SettingsStore,
        activityStream: ActivityFeedStream? = nil,
        insightsPolisher: InsightsEngine.Polisher? = nil
    ) {
        self.db = db
        self.settings = settings
        self.activityStream = activityStream ?? ActivityFeedStream(source: db)
        // The default stays entirely on-device: InsightsEngine's deterministic
        // first pass produces the card, and this optional polishing pass is skipped.
        self.insightsPolisher = insightsPolisher ?? { _ in
            throw InsightsPolisherError.notConfigured
        }
        self.topAppsWindow = settings.topAppsWindow
    }

    private enum InsightsPolisherError: Error { case notConfigured }

    /// View-driven task. Consumes the activity stream and refreshes the
    /// summary cards on a 60-s cadence. Cancellation propagates via
    /// `Task.isCancelled` when the view disappears.
    func task() async {
        await refresh()
        // `async let` lets us run the two loops concurrently without the
        // TaskGroup region-isolation checker tripping on @MainActor closures.
        async let activity: Void = consumeActivityStream()
        async let summary: Void  = periodicSummaryRefresh()
        _ = await (activity, summary)
    }

    private func consumeActivityStream() async {
        do {
            for try await batch in activityStream.events() {
                // Newest events first. Cap so the list doesn't grow without
                // bound across long sessions — the view only paints ~12.
                let merged = batch + recentActivity
                recentActivity = Array(merged.prefix(100))
            }
        } catch is CancellationError {
            return
        } catch {
            // Stream internals swallow non-cancellation errors with backoff;
            // anything that reaches us here means cancellation race — exit.
            return
        }
    }

    private func periodicSummaryRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            if Task.isCancelled { break }
            await refresh()
        }
    }

    /// Re-pulls `topApps` and `recentSessions` from the DB using the current
    /// `topAppsWindow`. Sessions always look at the last 24 h regardless of
    /// the picker (the picker is a Top Apps concept). Insights re-run on a
    /// 24-h frame window too — Pass 1 (heuristics) always; Pass 2 (LLM)
    /// only when the cache is stale AND `settings.aiInsightsEnabled` is on.
    func refresh() async {
        async let topAppsTask = loadTopApps()
        async let framesTask  = load24HourFrames()
        let (apps, frames) = await (topAppsTask, framesTask)
        self.topApps = apps
        self.recentSessions = SessionsService.cluster(frames)

        // Insights: serve from cache if fresh AND its polish-state still
        // matches the user's current toggle; otherwise compute Pass 1 +
        // optional Pass 2 and write the cache.
        let aiEnabled = settings.aiInsightsEnabled
        if let cached = InsightsEngine.loadCache(aiInsightsEnabled: aiEnabled) {
            self.insights = cached
            return
        }
        let heuristics = InsightsEngine.candidates(from: frames)
        let polished = await InsightsEngine.polish(
            heuristics,
            enabled: aiEnabled,
            polisher: insightsPolisher
        )
        self.insights = polished
        InsightsEngine.saveCache(
            polished,
            runtimeID: settings.synthesisRuntime.rawValue,
            aiPolished: aiEnabled
        )
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

    private func load24HourFrames() async -> [FrameRow] {
        do {
            return try await db.recentFrames(window: 24 * 60 * 60, limit: 1000)
        } catch {
            return []
        }
    }
}
