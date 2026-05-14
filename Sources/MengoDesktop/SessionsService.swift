import Foundation

/// Pure clustering of frames into display-ready sessions. No I/O — the
/// dashboard store calls `MemoryDB.recentFrames(window:limit:)` and feeds
/// the result here.
///
/// Algorithm:
/// 1. Sort frames ascending by timestamp (caller already does this).
/// 2. Walk frames; a gap > `gap` seconds between consecutive frames opens a
///    new session (regardless of app — different apps within the same time
///    cluster stay in one session).
/// 3. Drop sessions shorter than `minDuration` seconds.
/// 4. Title = "<dominantAppDisplayName> session" where dominant = the app
///    with the most frames in the session.
/// 5. Subtitle = the most-common `window_name` if it covers ≥ 40 % of frames;
///    otherwise "with <secondApp>" if a second app contributed; otherwise nil.
/// 6. App icons = top 3 distinct apps by frame count.
enum SessionsService {

    static func cluster(
        _ frames: [FrameRow],
        gap: TimeInterval = 300,
        minDuration: TimeInterval = 120
    ) -> [SessionRow] {
        guard !frames.isEmpty else { return [] }

        // 1 + 2: build raw time-clusters.
        var clusters: [[FrameRow]] = []
        var current: [FrameRow] = [frames[0]]
        for f in frames.dropFirst() {
            let last = current.last!
            if f.timestamp.timeIntervalSince(last.timestamp) > gap {
                clusters.append(current)
                current = [f]
            } else {
                current.append(f)
            }
        }
        clusters.append(current)

        // 3 + 4 + 5 + 6: render each cluster.
        return clusters.compactMap { rows in
            guard let first = rows.first, let last = rows.last else { return nil }
            let duration = last.timestamp.timeIntervalSince(first.timestamp)
            guard duration >= minDuration else { return nil }

            let appCounts = countBy(rows) { $0.appName }
            let dominantApp = appCounts.max { $0.value < $1.value }!.key
            let title = "\(AppUsageService.displayName(for: dominantApp)) session"

            // Subtitle: prefer dominant window_name (≥ 40 %); otherwise name
            // the second most-frequent app.
            let total = rows.count
            let windowCounts = countBy(rows.compactMap { $0.windowName }) { $0 }
            let topWindow = windowCounts.max { $0.value < $1.value }
            let subtitle: String? = {
                if let topWindow, Double(topWindow.value) / Double(total) >= 0.4 {
                    return topWindow.key
                }
                let secondApp = appCounts
                    .filter { $0.key != dominantApp }
                    .max { $0.value < $1.value }?.key
                return secondApp.map { "with \(AppUsageService.displayName(for: $0))" }
            }()

            let appIcons = appCounts
                .sorted { $0.value > $1.value }
                .prefix(3)
                .map { AppUsageService.iconName(for: $0.key) }

            return SessionRow(
                id: UUID(),
                title: title,
                subtitle: subtitle,
                startedAt: first.timestamp,
                endedAt: last.timestamp,
                frameCount: total,
                appIcons: Array(appIcons)
            )
        }
    }

    // MARK: -

    private static func countBy<T, K: Hashable>(_ xs: [T], _ key: (T) -> K) -> [K: Int] {
        var out: [K: Int] = [:]
        for x in xs { out[key(x), default: 0] += 1 }
        return out
    }
}
