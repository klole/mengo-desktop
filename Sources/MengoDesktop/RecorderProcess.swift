import Foundation

/// The recorder-process operations `RecorderController` depends on. Lets tests
/// drive the controller with a stub instead of spawning the real recorder.
protocol RecorderProcessControlling: AnyObject {
    var isRunning: Bool { get }
    func start(binaryURL: URL, extraArguments: [String]) throws
    func stop()
}

/// Spawns and tears down the bundled recorder helper (`screenpipe record`). Ported
/// from V1's `ScreenpipeMenu/RecorderProcess.swift`; log path renamed to MengoDesktop.
final class RecorderProcess: RecorderProcessControlling {
    private var process: Process?
    private var logHandle: FileHandle?
    let token: String
    let logFileURL: URL

    init(token: String) {
        self.token = token
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MengoDesktop", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("recorder.log")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Spawn `binaryURL record [extraArguments…]` with our auth token in the env.
    /// Truncates the log on each start.
    func start(binaryURL: URL, extraArguments: [String]) throws {
        guard !isRunning else { return }

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logFileURL)
        self.logHandle = handle

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["record"] + extraArguments
        var env = ProcessInfo.processInfo.environment
        env["SCREENPIPE_API_KEY"] = token
        // .app processes launched via Finder get a minimal PATH that omits the user's
        // shell paths — and the recorder needs to find ffmpeg. Prepend common locations.
        let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin:\(NSHomeDirectory())/bin:\(existingPath)"
        proc.environment = env
        proc.standardOutput = handle
        proc.standardError = handle

        try proc.run()
        self.process = proc
    }

    /// SIGTERM, wait up to 3 s, then SIGKILL.
    func stop() {
        guard let proc = process, proc.isRunning else {
            try? logHandle?.close(); logHandle = nil; process = nil
            return
        }
        proc.terminate()
        let deadline = Date().addingTimeInterval(3)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if proc.isRunning {
            kill(proc.processIdentifier, SIGKILL)
            proc.waitUntilExit()
        }
        try? logHandle?.close()
        logHandle = nil
        process = nil
    }

    static func newToken() -> String {
        let hex = (0..<8).map { _ in String(format: "%x", Int.random(in: 0..<16)) }.joined()
        return "sp-\(hex)"
    }
}
