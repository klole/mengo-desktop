import Foundation

/// Minimal file logger. A Finder-launched `.app` has no attached terminal,
/// so `bootstrap()` redirects stdout/stderr into a log file; `line(_:)`
/// appends a timestamped line. Adapted from V1's `ScreenpipeFlow/Logger`.
enum Log {

    /// `~/Library/Logs/MengoDesktop/` — created on first access.
    static let directory: URL = {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/MengoDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// `~/Library/Logs/MengoDesktop/app.log`.
    static let fileURL: URL = directory.appendingPathComponent("app.log")

    /// Call once at process start (from `MengoDesktopApp.init()`). Redirects
    /// stdout + stderr to `app.log` (unbuffered) and writes a launch line.
    static func bootstrap() {
        freopen(fileURL.path, "a+", stdout)
        freopen(fileURL.path, "a+", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        line("app launched, pid=\(getpid())")
    }

    /// Append a timestamped line to `app.log` (via the redirected stdout).
    static func line(_ message: String) {
        print("[\(Date())] \(message)")
    }

    /// `~/Library/Logs/MengoDesktop/synthesis-<id>.log` — per-synthesis subprocess output.
    static func synthesisLogURL(id: String) -> URL {
        directory.appendingPathComponent("synthesis-\(id).log")
    }
}
