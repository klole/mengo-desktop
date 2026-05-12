import Foundation

enum SynthesisResult: Equatable {
    case success(outputDir: URL, slug: String)
    case failure(message: String)
}

enum SynthesisRunner {

    enum RunError: Error, LocalizedError {
        case timeout
        case spawnFailed(String)

        var errorDescription: String? {
            switch self {
            case .timeout: return "Synthesis subprocess timed out"
            case .spawnFailed(let s): return "Failed to spawn synthesis subprocess: \(s)"
            }
        }
    }

    /// Spawns `command` with `arguments`, captures all output to `logFile`, and
    /// parses the LAST line of stdout matching the success/failure JSON contract.
    /// Throws on timeout or spawn failure.
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

        // Capture stdout into memory for parsing the final status line; mirror
        // both streams to the log file.
        let stdoutBuffer = StdoutBuffer()

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            stdoutBuffer.append(chunk)
            try? logHandle.write(contentsOf: chunk)
        }
        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty { return }
            try? logHandle.write(contentsOf: chunk)
        }

        do {
            try process.run()
        } catch {
            throw RunError.spawnFailed("\(error)")
        }

        // Race process exit against timeout.
        let processTask = Task.detached(priority: .userInitiated) { @Sendable in
            process.waitUntilExit()
        }
        let timeoutTask = Task.detached(priority: .background) { @Sendable in
            try await Task.sleep(for: .seconds(timeoutSeconds))
            if process.isRunning { process.terminate() }
        }
        await processTask.value
        timeoutTask.cancel()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        // Drain final buffered bytes.
        if let rest = try? stdoutPipe.fileHandleForReading.readToEnd() {
            stdoutBuffer.append(rest)
            try? logHandle.write(contentsOf: rest)
        }
        if let rest = try? stderrPipe.fileHandleForReading.readToEnd() {
            try? logHandle.write(contentsOf: rest)
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

/// Thread-safe append-only buffer for piping subprocess stdout into memory.
/// Process readabilityHandlers fire on a background queue; we need atomic append.
private final class StdoutBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(chunk)
    }
}
