import Foundation

final class RecorderProcess {
    private var process: Process?
    private var logHandle: FileHandle?
    let token: String
    let logFileURL: URL

    init(token: String) {
        self.token = token
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ScreenpipeMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        self.logFileURL = logsDir.appendingPathComponent("recorder.log")
    }

    var isRunning: Bool { process?.isRunning ?? false }

    /// Spawn `binaryURL record` with our auth token set via env. Truncates the log on each start.
    func start(binaryURL: URL) throws {
        guard !isRunning else { return }

        FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logFileURL)
        self.logHandle = handle

        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["record"]
        var env = ProcessInfo.processInfo.environment
        env["SCREENPIPE_API_KEY"] = token
        proc.environment = env
        proc.standardOutput = handle
        proc.standardError = handle

        try proc.run()
        self.process = proc
    }

    /// SIGTERM, wait up to 3s, then SIGKILL.
    func stop() {
        guard let proc = process, proc.isRunning else { return }
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
