import Foundation

actor ScreenpipeClient {
    struct Health {
        let isHealthy: Bool
        let audioStatus: AudioStatus
    }

    enum AudioStatus: String {
        case running
        case paused
        case unknown
    }

    struct ThumbnailItem: Equatable, Hashable {
        let timestamp: Date
        let appName: String
        let windowName: String
    }

    enum ClientError: Error, LocalizedError {
        case notRunning
        case decode(String)
        case http(Int)
        case unauthorized

        var errorDescription: String? {
            switch self {
            case .notRunning: return "screenpipe is not running on 127.0.0.1:3030"
            case .decode(let s): return "screenpipe response malformed: \(s)"
            case .http(let code): return "screenpipe returned HTTP \(code)"
            case .unauthorized: return "screenpipe API needs an API key — fetch via `screenpipe auth token`"
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let token: String?

    /// `token` is sent as `Authorization: Bearer <token>` on every request when
    /// non-nil. Required for /search; optional for /health.
    init(baseURL: URL = URL(string: "http://127.0.0.1:3030")!,
         session: URLSession = .shared,
         token: String? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
    }

    func health() async throws -> Health {
        var req = URLRequest(url: baseURL.appendingPathComponent("health"))
        req.timeoutInterval = 3
        attachAuth(&req)
        let (data, response) = try await dataOrConnectErr(req)
        try Self.checkStatus(response)
        return try Self.parseHealth(data)
    }

    /// Thumbnail-index items over a time range, sorted oldest first.
    /// /search requires auth; throws `.unauthorized` if no token was provided.
    func thumbnailIndex(from start: Date,
                        to end: Date,
                        limit: Int = 200) async throws -> [ThumbnailItem] {
        guard token != nil else { throw ClientError.unauthorized }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var components = URLComponents(url: baseURL.appendingPathComponent("search"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "content_type", value: "ocr"),
            URLQueryItem(name: "start_time", value: iso.string(from: start)),
            URLQueryItem(name: "end_time", value: iso.string(from: end)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        var req = URLRequest(url: components.url!)
        req.timeoutInterval = 10
        attachAuth(&req)
        let (data, response) = try await dataOrConnectErr(req)
        try Self.checkStatus(response)
        return try Self.parseThumbnailIndex(data)
    }

    // MARK: - Pure parsers (exposed for tests)

    static func parseHealth(_ data: Data) throws -> Health {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClientError.decode("not a JSON object")
        }
        let status = (json["status"] as? String) ?? ""
        let audio = (json["audio_status"] as? String) ?? ""
        let isHealthy = status == "healthy"
        let audioStatus: AudioStatus = {
            switch audio.lowercased() {
            case "ok", "running": return .running
            case "paused": return .paused
            default: return .unknown
            }
        }()
        return Health(isHealthy: isHealthy, audioStatus: audioStatus)
    }

    static func parseThumbnailIndex(_ data: Data) throws -> [ThumbnailItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw ClientError.decode("expected {data: [...]}")
        }

        var items: [ThumbnailItem] = []
        for entry in arr {
            guard (entry["type"] as? String) == "OCR",
                  let content = entry["content"] as? [String: Any],
                  let ts = content["timestamp"] as? String,
                  let date = parseISO8601(ts) else {
                continue
            }
            let app = (content["app_name"] as? String) ?? ""
            let window = (content["window_name"] as? String) ?? ""
            items.append(ThumbnailItem(timestamp: date, appName: app, windowName: window))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    /// screenpipe emits ISO8601 with optional fractional seconds and optional
    /// timezone offset. `ISO8601DateFormatter` is strict — it parses one or the
    /// other but not both flexibly. Try fractional first (real screenpipe format),
    /// fall back to integer-second (our fixtures, and what we emit ourselves).
    static func parseISO8601(_ s: String) -> Date? {
        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFractional.date(from: s) { return d }
        let withoutFractional = ISO8601DateFormatter()
        withoutFractional.formatOptions = [.withInternetDateTime]
        return withoutFractional.date(from: s)
    }

    // MARK: - Helpers

    private func attachAuth(_ req: inout URLRequest) {
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    }

    private static func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ClientError.http(-1)
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.http(http.statusCode)
        }
    }

    private func dataOrConnectErr(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch let err as URLError where err.code == .cannotConnectToHost || err.code == .timedOut {
            throw ClientError.notRunning
        }
    }
}

/// Locates the screenpipe binary on disk and asks it for the active API token.
/// Returns nil if the binary isn't found or the call fails. Cheap to call once
/// at startup; ScreenpipeFlow holds the result for the session.
enum ScreenpipeTokenProvider {
    static func discover() -> String? {
        guard let binary = findBinary() else { return nil }
        let process = Process()
        process.executableURL = binary
        process.arguments = ["auth", "token"]
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = (try? outPipe.fileHandleForReading.readToEnd()) ?? Data()
        let token = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token?.isEmpty == false ? token : nil
    }

    private static func findBinary() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent("Library/Application Support/ScreenpipeMenu/bin/screenpipe"),
            home.appendingPathComponent("Applications/ScreenpipeMenu.app/Contents/Helpers/screenpipe"),
            URL(fileURLWithPath: "/Applications/ScreenpipeMenu.app/Contents/Helpers/screenpipe"),
            URL(fileURLWithPath: "/opt/homebrew/bin/screenpipe"),
            URL(fileURLWithPath: "/usr/local/bin/screenpipe")
        ]
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return url
        }
        return nil
    }
}
