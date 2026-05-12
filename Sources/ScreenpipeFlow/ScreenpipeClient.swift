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

    enum ClientError: Error, LocalizedError {
        case notRunning
        case decode(String)
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .notRunning: return "screenpipe is not running on 127.0.0.1:3030"
            case .decode(let s): return "screenpipe response malformed: \(s)"
            case .http(let code): return "screenpipe returned HTTP \(code)"
            }
        }
    }

    struct ThumbnailItem: Equatable {
        let timestamp: Date
        let appName: String
        let windowName: String
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:3030")!,
         session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func health() async throws -> Health {
        let url = baseURL.appendingPathComponent("health")
        var req = URLRequest(url: url)
        req.timeoutInterval = 3
        let (data, response) = try await dataOrConnectErr(req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.parseHealth(data)
    }

    /// Pure parsing — testable without network.
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

    /// Thumbnail-index items over a time range, sorted oldest first.
    /// We don't pull pixel data here — the Timeline window fetches frames
    /// lazily for the visible subset only.
    func thumbnailIndex(from start: Date,
                        to end: Date,
                        limit: Int = 200) async throws -> [ThumbnailItem] {
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
        let (data, response) = try await dataOrConnectErr(req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClientError.http((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        return try Self.parseThumbnailIndex(data)
    }

    static func parseThumbnailIndex(_ data: Data) throws -> [ThumbnailItem] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = json["data"] as? [[String: Any]] else {
            throw ClientError.decode("expected {data: [...]}")
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var items: [ThumbnailItem] = []
        for entry in arr {
            guard (entry["type"] as? String) == "OCR",
                  let content = entry["content"] as? [String: Any],
                  let ts = content["timestamp"] as? String,
                  let date = iso.date(from: ts) else {
                continue
            }
            let app = (content["app_name"] as? String) ?? ""
            let window = (content["window_name"] as? String) ?? ""
            items.append(ThumbnailItem(timestamp: date, appName: app, windowName: window))
        }
        return items.sorted { $0.timestamp < $1.timestamp }
    }

    private func dataOrConnectErr(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch let err as URLError where err.code == .cannotConnectToHost || err.code == .timedOut {
            throw ClientError.notRunning
        }
    }
}
