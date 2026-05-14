import Foundation

/// Pure formatting/parsing helpers for the Memory pane. No UI, no I/O.
enum MemoryFormatting {

    /// e.g. "3.2 GB". Uses the OS file-size formatter.
    static func bytes(_ count: Int64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: count)
    }

    /// e.g. "4m 17s", "2h 14m", "0s". Two largest non-zero units.
    static func duration(seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// "just now" (< 60 s), "N minute(s) ago" (< 60 min), else a short clock time ("3:14 PM").
    static func relative(from date: Date, now: Date = Date()) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 { return "just now" }
        if delta < 3600 {
            let mins = Int(delta / 60)
            return "\(mins) minute\(mins == 1 ? "" : "s") ago"
        }
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Parse a recorder timestamp string leniently. Returns nil rather than throwing,
    /// so a malformed value never breaks a `/health` decode that carries it elsewhere.
    static func parseTimestamp(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
