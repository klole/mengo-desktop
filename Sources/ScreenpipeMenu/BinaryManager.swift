import Foundation

enum BinaryManager {
    enum Error: Swift.Error {
        case versionFieldMissing
        case downloadFailed(statusCode: Int)
        case extractionFailed(stderr: String)
    }

    static func currentArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let cstr = raw.bindMemory(to: CChar.self).baseAddress!
            return String(cString: cstr)
        }
        return machine == "arm64" ? "arm64" : "x64"
    }

    static func tarballURL(version: String, arch: String) -> URL {
        URL(string: "https://registry.npmjs.org/@screenpipe/cli-darwin-\(arch)/-/cli-darwin-\(arch)-\(version).tgz")!
    }

    static func parseLatestVersion(from data: Data) throws -> String {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let version = json["version"] as? String
        else {
            throw Error.versionFieldMissing
        }
        return version
    }

    static let appSupportDir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScreenpipeMenu", isDirectory: true)
    }()

    static var binDir: URL { appSupportDir.appendingPathComponent("bin", isDirectory: true) }
    static var binaryURL: URL { binDir.appendingPathComponent("screenpipe") }
    static var versionFileURL: URL { appSupportDir.appendingPathComponent("version.txt") }

    /// Returns the path to a runnable screenpipe binary, downloading on first call.
    static func ensureBinary(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if FileManager.default.isExecutableFile(atPath: binaryURL.path) {
            return binaryURL
        }

        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)

        let version = try await fetchLatestVersion()
        let url = tarballURL(version: version, arch: currentArch())
        let tarballPath = appSupportDir.appendingPathComponent("screenpipe-\(version).tgz")
        try await download(from: url, to: tarballPath, progress: progress)
        try extract(tarball: tarballPath, into: binDir)
        try? FileManager.default.removeItem(at: tarballPath)
        try? version.write(to: versionFileURL, atomically: true, encoding: .utf8)

        // Mark binary executable.
        try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                               ofItemAtPath: binaryURL.path)
        return binaryURL
    }

    static func fetchLatestVersion() async throws -> String {
        let url = URL(string: "https://registry.npmjs.org/screenpipe/latest")!
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Error.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try parseLatestVersion(from: data)
    }

    static func download(from url: URL, to destination: URL,
                         progress: @escaping @Sendable (Double) -> Void) async throws {
        let delegate = DownloadProgressDelegate(progress: progress)
        let (tempURL, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw Error.downloadFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    static func extract(tarball: URL, into directory: URL) throws {
        // npm tarball layout: package/bin/{screenpipe, mlx.metallib}.
        // --strip-components=2 drops "package/bin/" so both files land directly in `directory`.
        // mlx.metallib must live next to the binary — the recorder loads it at runtime.
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        proc.arguments = ["-xzf", tarball.path, "-C", directory.path,
                          "--strip-components=2", "package/bin/"]
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                             encoding: .utf8) ?? ""
            throw Error.extractionFailed(stderr: err)
        }
    }
}

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
}
