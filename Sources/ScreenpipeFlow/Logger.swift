import Foundation

enum Logger {
    static let logsDir: URL = {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("Logs/ScreenpipeFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let appLogURL: URL = logsDir.appendingPathComponent("app.log")

    /// Redirect stdout + stderr to the app log file. Call once at process start
    /// — when launched via Finder there's no attached terminal, so `print` goes
    /// nowhere unless we redirect.
    static func bootstrap() {
        freopen(appLogURL.path, "a+", stdout)
        freopen(appLogURL.path, "a+", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        log("app launched, pid=\(getpid())")
    }

    static func log(_ msg: String) {
        print("[\(Date())] \(msg)")
    }

    /// Per-synthesis subprocess log file. Caller writes to it and surfaces in UI on failure.
    static func synthesisLogURL(id: String) -> URL {
        logsDir.appendingPathComponent("synthesis-\(id).log")
    }
}
