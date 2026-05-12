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
}
