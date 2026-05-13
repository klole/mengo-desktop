import Foundation

/// Locates the bundled `screenpipe` helper. Ported from V1's
/// `ScreenpipeMenu/BinaryManager.swift`. The binary is embedded at build time
/// (`build-mengo.sh`) — bundling, rather than downloading at runtime, is what
/// lets the spawned helper inherit Mengo Desktop's Screen Recording / Microphone
/// TCC grants (macOS treats helpers inside a sealed `.app` as part of the parent).
enum BinaryManager {
    enum BinaryError: Swift.Error {
        case binaryNotFound(searched: String)
    }

    static var binaryURL: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/screenpipe")
    }

    static func ensureBinary() throws -> URL {
        let path = binaryURL.path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw BinaryError.binaryNotFound(searched: path)
        }
        return binaryURL
    }

    /// Read the bundled screenpipe version via `--version`. Blocks briefly — only
    /// called during recorder startup.
    static func bundledVersion() -> String? {
        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else { return nil }
        let proc = Process()
        proc.executableURL = binaryURL
        proc.arguments = ["--version"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // `screenpipe --version` prints e.g. "screenpipe 0.3.327".
        return text.split(separator: " ").last.map(String.init)
    }
}
