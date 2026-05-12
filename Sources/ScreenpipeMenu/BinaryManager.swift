import Foundation

enum BinaryManager {
    enum Error: Swift.Error {
        case binaryNotFound(searched: String)
    }

    /// The screenpipe binary is bundled inside the .app at build time
    /// (Contents/Helpers/screenpipe). Bundling — rather than downloading at runtime —
    /// is what lets the spawned recorder inherit ScreenpipeMenu's Screen Recording
    /// and Microphone TCC grants: macOS treats helpers inside a sealed .app bundle
    /// as part of the parent, instead of their own responsible process.
    static var binaryURL: URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/screenpipe")
    }

    static func ensureBinary() throws -> URL {
        let path = binaryURL.path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw Error.binaryNotFound(searched: path)
        }
        return binaryURL
    }

    /// Read the bundled screenpipe version by invoking `--version`. Cheap, but blocks
    /// briefly — only called during bootstrap.
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
