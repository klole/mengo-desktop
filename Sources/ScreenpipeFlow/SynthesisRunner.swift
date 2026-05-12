import Foundation

enum SynthesisResult: Equatable {
    case success(outputDir: URL, slug: String)
    case failure(message: String)
}

enum SynthesisRunner {

    enum RunError: Error, LocalizedError {
        case spawnFailed(String)

        var errorDescription: String? {
            switch self {
            case .spawnFailed(let s): return "Failed to spawn synthesis subprocess: \(s)"
            }
        }
    }

    /// Spawns `command` with `arguments`, captures all output to `logFile`, and
    /// parses the LAST line of stdout matching the success/failure JSON contract.
    /// Returns `.failure` on timeout, subprocess error, or contract violation.
    /// Throws only on spawn failure.
    static func run(
        command: URL,
        arguments: [String],
        logFile: URL,
        timeoutSeconds: TimeInterval
    ) async throws -> SynthesisResult {
        try FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logFile)
        defer { try? logHandle.close() }

        let process = Process()
        process.executableURL = command
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // FileHandle.write is not thread-safe; readabilityHandlers for the two
        // pipes fire on different queues. Serialize log writes through one writer.
        let logWriter = LogWriter(handle: logHandle)
        let stdoutBuffer = StdoutBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            stdoutBuffer.append(chunk)
            logWriter.write(chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            logWriter.write(chunk)
        }

        do {
            try process.run()
        } catch {
            throw RunError.spawnFailed("\(error)")
        }

        // Race process exit against timeout.
        let timedOut = TimedOutFlag()
        let processTask = Task.detached(priority: .userInitiated) { @Sendable in
            process.waitUntilExit()
        }
        let timeoutTask = Task.detached(priority: .background) { @Sendable in
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            if process.isRunning {
                timedOut.set()
                process.terminate()
            }
        }
        await processTask.value
        timeoutTask.cancel()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain final buffered bytes.
        if let rest = try? stdoutPipe.fileHandleForReading.readToEnd() {
            stdoutBuffer.append(rest)
            logWriter.write(rest)
        }
        if let rest = try? stderrPipe.fileHandleForReading.readToEnd() {
            logWriter.write(rest)
        }

        if timedOut.value {
            return .failure(message: "synthesis timed out after \(Int(timeoutSeconds))s")
        }
        if process.terminationStatus != 0 {
            return .failure(message: "subprocess exited with status \(process.terminationStatus)")
        }

        return parseLastStatusLine(stdout: stdoutBuffer.data)
    }

    static func parseLastStatusLine(stdout: Data) -> SynthesisResult {
        guard let text = String(data: stdout, encoding: .utf8) else {
            return .failure(message: "subprocess stdout was not valid UTF-8")
        }
        // Walk from end; first line that parses as JSON object with "status" wins.
        for line in text.split(separator: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { continue }
            guard let data = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = json["status"] as? String else {
                continue
            }
            if status == "ok" {
                guard let dirStr = json["outputDir"] as? String,
                      let slug = json["slug"] as? String else {
                    return .failure(message: "status=ok but missing outputDir/slug")
                }
                return .success(outputDir: URL(fileURLWithPath: dirStr), slug: slug)
            } else {
                let msg = (json["message"] as? String) ?? "unknown error"
                return .failure(message: msg)
            }
        }
        return .failure(message: "no {\"status\":...} JSON line found in subprocess stdout")
    }
}

/// Serializes log writes from both stdout+stderr readabilityHandlers.
/// FileHandle.write(contentsOf:) is not documented as thread-safe.
private final class LogWriter: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    init(handle: FileHandle) { self.handle = handle }
    func write(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        try? handle.write(contentsOf: chunk)
    }
}

/// Thread-safe append-only buffer for piping subprocess stdout into memory.
private final class StdoutBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data = Data()
    func append(_ chunk: Data) {
        lock.lock(); defer { lock.unlock() }
        data.append(chunk)
    }
}

/// One-shot boolean for "did the timeout fire before the process exited?"
private final class TimedOutFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.lock(); defer { lock.unlock() }; return _value }
    func set() { lock.lock(); _value = true; lock.unlock() }
}
