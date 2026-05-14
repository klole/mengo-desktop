import Foundation

/// A display the recorder can capture. From `screenpipe vision list -o json`.
struct MonitorInfo: Equatable, Identifiable, Sendable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    let isDefault: Bool
}

/// An audio device the recorder can capture. From `screenpipe audio list -o json`.
/// `name` is what the recorder CLI wants on the command line (suffix included);
/// `displayName` strips the trailing `(input)`/`(output)` for the UI.
struct AudioDeviceInfo: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable { case input, output, unknown }
    let name: String
    let isDefault: Bool
    var id: String { name }

    var kind: Kind {
        if name.hasSuffix("(input)") { return .input }
        if name.hasSuffix("(output)") { return .output }
        return .unknown
    }

    var displayName: String {
        for suffix in [" (input)", " (output)", "(input)", "(output)"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }
        return name
    }
}

/// Enumerates the displays / audio devices available to record. Implementations
/// must be safe to call when the recorder isn't running.
protocol RecordingSourceCatalog: Sendable {
    func availableMonitors() async throws -> [MonitorInfo]
    func availableAudioDevices() async throws -> [AudioDeviceInfo]
}

/// Shells out to the bundled recorder helper's `vision list` / `audio list`
/// subcommands (JSON output). Runs the subprocess off the main actor.
struct RecorderCLICatalog: RecordingSourceCatalog {
    var binaryURL: @Sendable () throws -> URL = { try BinaryManager.ensureBinary() }

    func availableMonitors() async throws -> [MonitorInfo] {
        let data = try await runJSON(["vision", "list", "-o", "json"])
        return try SourceCatalog.decodeMonitors(from: data)
    }

    func availableAudioDevices() async throws -> [AudioDeviceInfo] {
        let data = try await runJSON(["audio", "list", "-o", "json"])
        return try SourceCatalog.decodeAudioDevices(from: data)
    }

    private func runJSON(_ args: [String]) async throws -> Data {
        let url = try binaryURL()
        return try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = url
            proc.arguments = args
            var env = ProcessInfo.processInfo.environment
            let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(existingPath)"
            proc.environment = env
            let out = Pipe(); proc.standardOutput = out
            proc.standardError = Pipe()
            try proc.run()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            return data
        }.value
    }
}

/// Pure decoders — split out so tests don't need a subprocess.
enum SourceCatalog {
    private struct MonitorsResponse: Decodable {
        struct Item: Decodable { let id: Int; let name: String; let width: Int; let height: Int; let is_default: Bool }
        let data: [Item]
    }
    private struct AudioResponse: Decodable {
        struct Item: Decodable { let name: String; let is_default: Bool }
        let data: [Item]
    }

    static func decodeMonitors(from data: Data) throws -> [MonitorInfo] {
        try JSONDecoder().decode(MonitorsResponse.self, from: data).data.map {
            MonitorInfo(id: $0.id, name: $0.name, width: $0.width, height: $0.height, isDefault: $0.is_default)
        }
    }

    static func decodeAudioDevices(from data: Data) throws -> [AudioDeviceInfo] {
        try JSONDecoder().decode(AudioResponse.self, from: data).data.map {
            AudioDeviceInfo(name: $0.name, isDefault: $0.is_default)
        }
    }
}
