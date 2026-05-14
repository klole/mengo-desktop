import Foundation

/// Two-pass insight surfacer.
///
/// **Pass 1 (this file, no LLM):** heuristic detectors that scan recent
/// frames for app-pair workflow signals, repeated window-name patterns
/// (likely an automation target), and long uninterrupted focus blocks.
/// Each candidate carries a templated `title` + `body` so the dashboard can
/// show something useful without any AI dependency.
///
/// **Pass 2 (D3, opt-in):** when `SettingsStore.aiInsightsEnabled` is true
/// and the user's chosen `SynthesisRuntime` is available, one batched CLI
/// call rewrites `title`/`body` per candidate with nicer prose. Pass 2
/// preserves the `kind` and `cta` from Pass 1 — only the strings change.
enum InsightsEngine {

    // MARK: - Pass 2 (opt-in LLM polish)

    /// Replacement strings handed back by the polisher. The engine merges
    /// these onto the heuristic candidates by `id` — `kind` and `cta` never
    /// change in the polish step.
    struct PolishedText: Equatable, Sendable, Codable {
        let id: UUID
        let title: String
        let body: String
    }

    /// Stable closure interface: take the candidates, return polished strings.
    /// In production the closure shells out to the user's Claude Code / Codex
    /// CLI; in tests it's a stub that returns canned data (or throws).
    typealias Polisher = @Sendable ([Insight]) async throws -> [PolishedText]

    /// Optionally rewrites `title`/`body` for each candidate using the
    /// user-supplied polisher. When `enabled` is false the candidates pass
    /// through unchanged; when the polisher throws, the candidates also pass
    /// through unchanged (the dashboard remains useful even with a flaky CLI).
    static func polish(
        _ candidates: [Insight],
        enabled: Bool,
        polisher: Polisher
    ) async -> [Insight] {
        guard enabled, !candidates.isEmpty else { return candidates }
        let polished: [PolishedText]
        do { polished = try await polisher(candidates) }
        catch { return candidates }

        let byID = Dictionary(uniqueKeysWithValues: polished.map { ($0.id, $0) })
        return candidates.map { c in
            guard let p = byID[c.id] else { return c }
            var copy = c
            copy.title = p.title
            copy.body  = p.body
            return copy
        }
    }

    // MARK: - Disk cache

    struct Cache: Codable, Equatable, Sendable {
        let generatedAt: Date
        let runtimeID: String
        let insights: [Insight]
    }

    /// Default cache location — App Support, per the spec.
    static var defaultCacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MengoDesktop", isDirectory: true)
            .appendingPathComponent("insights-cache.json")
    }

    /// Returns the cached insights if the file exists and was written within
    /// `maxAge` seconds. Otherwise returns nil (no error — refresh fall-through).
    static func loadCache(from url: URL = defaultCacheURL, maxAge: TimeInterval = 600, now: Date = Date()) -> [Insight]? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder.iso8601.decode(Cache.self, from: data),
              now.timeIntervalSince(cache.generatedAt) < maxAge
        else { return nil }
        return cache.insights
    }

    /// Persists the (polished) insights so the next launch / pane navigation
    /// doesn't re-trigger the LLM call inside the 10-min window.
    static func saveCache(_ insights: [Insight], runtimeID: String, to url: URL = defaultCacheURL, now: Date = Date()) {
        let cache = Cache(generatedAt: now, runtimeID: runtimeID, insights: insights)
        guard let data = try? JSONEncoder.iso8601.encode(cache) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - Pass 1 (heuristic — always on, no LLM)

    /// Top 4 candidates by signal score, surfaced for the dashboard carousel.
    static func candidates(from frames: [FrameRow], referenceTime: Date = Date()) -> [Insight] {
        guard !frames.isEmpty else { return [] }
        var all: [Insight] = []
        all += detectAppPairs(frames)
        all += detectRepeatedWindowPattern(frames)
        all += detectFocusBlocks(frames)
        return Array(all.sorted { $0.signal > $1.signal }.prefix(4))
    }

    // MARK: - App pair detection (workflowDetected)

    /// Walk frames in time order, reduce to a deduplicated app sequence
    /// (drop consecutive runs of the same app), then count adjacent-pair
    /// transitions. Pairs that appear ≥ `minOccurrences` times are
    /// candidates.
    private static func detectAppPairs(_ frames: [FrameRow], minOccurrences: Int = 3) -> [Insight] {
        // Reduce to distinct-app sequence.
        let appSequence = frames.reduce(into: [String]()) { acc, f in
            if acc.last != f.appName { acc.append(f.appName) }
        }
        guard appSequence.count >= 2 else { return [] }

        var pairCounts: [Pair: Int] = [:]
        for i in 0..<(appSequence.count - 1) {
            let pair = Pair(from: appSequence[i], to: appSequence[i + 1])
            pairCounts[pair, default: 0] += 1
        }

        return pairCounts
            .filter { $0.value >= minOccurrences }
            .map { (pair, count) in
                let from = AppUsageService.displayName(for: pair.from)
                let to   = AppUsageService.displayName(for: pair.to)
                return Insight(
                    id: UUID(),
                    kind: .workflowDetected,
                    title: InsightKind.workflowDetected.headline,
                    body: "You moved from \(from) to \(to) \(count) times today. Worth automating?",
                    cta: .createFlow(seed: slugify("\(pair.from)-to-\(pair.to)")),
                    signal: Double(count)
                )
            }
    }

    // MARK: - Repeated window/file pattern (automationOpportunity)

    /// Bucket frames by time-gap > 5 min. A `window_name` that appears in
    /// `minClusters` or more separate buckets is a candidate.
    private static func detectRepeatedWindowPattern(_ frames: [FrameRow], minClusters: Int = 3) -> [Insight] {
        let clusters = timeClusters(frames, gapSeconds: 300)
        guard clusters.count >= minClusters else { return [] }

        var windowClusterCounts: [String: Int] = [:]
        for cluster in clusters {
            let windowsHere = Set(cluster.compactMap { $0.windowName?.isEmpty == false ? $0.windowName : nil })
            for w in windowsHere { windowClusterCounts[w, default: 0] += 1 }
        }

        return windowClusterCounts
            .filter { $0.value >= minClusters }
            .map { (window, clusterCount) in
                let label = extractFilename(from: window) ?? window
                return Insight(
                    id: UUID(),
                    kind: .automationOpportunity,
                    title: InsightKind.automationOpportunity.headline,
                    body: "You worked on \"\(label)\" across \(clusterCount) separate sessions today. Worth turning into a skill?",
                    cta: .createSkill(seed: slugify(label)),
                    signal: Double(clusterCount)
                )
            }
    }

    // MARK: - Focus block (focusPattern)

    /// Longest uninterrupted single-app stretch in the input. Emits a
    /// candidate only when it exceeds `minDurationSeconds`.
    private static func detectFocusBlocks(_ frames: [FrameRow], minDurationSeconds: TimeInterval = 3600) -> [Insight] {
        guard !frames.isEmpty else { return [] }

        var bestApp = frames[0].appName
        var bestStart = frames[0].timestamp
        var bestEnd = frames[0].timestamp
        var bestDuration: TimeInterval = 0

        var currentApp = frames[0].appName
        var currentStart = frames[0].timestamp
        var lastTimestamp = frames[0].timestamp

        for f in frames.dropFirst() {
            let gap = f.timestamp.timeIntervalSince(lastTimestamp)
            if f.appName == currentApp && gap < 300 {
                let dur = f.timestamp.timeIntervalSince(currentStart)
                if dur > bestDuration {
                    bestDuration = dur
                    bestApp = currentApp
                    bestStart = currentStart
                    bestEnd = f.timestamp
                }
                lastTimestamp = f.timestamp
            } else {
                currentApp = f.appName
                currentStart = f.timestamp
                lastTimestamp = f.timestamp
            }
        }

        guard bestDuration >= minDurationSeconds else { return [] }
        let appName = AppUsageService.displayName(for: bestApp)
        let minutes = Int(bestDuration / 60)
        return [Insight(
            id: UUID(),
            kind: .focusPattern,
            title: InsightKind.focusPattern.headline,
            body: "Your longest focus block today: \(minutes) minutes in \(appName).",
            cta: .viewMemory(startedAt: bestStart, endedAt: bestEnd),
            signal: bestDuration / 3600
        )]
    }

    // MARK: - Helpers

    private struct Pair: Hashable {
        let from: String
        let to: String
    }

    private static func timeClusters(_ frames: [FrameRow], gapSeconds: TimeInterval) -> [[FrameRow]] {
        guard !frames.isEmpty else { return [] }
        var clusters: [[FrameRow]] = []
        var current: [FrameRow] = [frames[0]]
        for f in frames.dropFirst() {
            let last = current.last!
            if f.timestamp.timeIntervalSince(last.timestamp) > gapSeconds {
                clusters.append(current); current = [f]
            } else {
                current.append(f)
            }
        }
        clusters.append(current)
        return clusters
    }

    /// Pull "shopify-product.csv" out of "shopify-product.csv — VS Code" or
    /// similar separator-delimited window titles. Returns nil if nothing
    /// resembling a filename is present.
    private static func extractFilename(from window: String) -> String? {
        let separators: [String] = [" — ", " - ", " · ", " | "]
        for sep in separators {
            if let range = window.range(of: sep) {
                let candidate = String(window[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                if !candidate.isEmpty { return candidate }
            }
        }
        return nil
    }

    private static func slugify(_ s: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let lower = s.lowercased()
        let mapped = lower.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(mapped).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return collapsed.isEmpty ? "insight" : String(collapsed.prefix(60))
    }
}
