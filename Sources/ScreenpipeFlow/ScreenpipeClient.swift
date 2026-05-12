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

    private func dataOrConnectErr(_ req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch let err as URLError where err.code == .cannotConnectToHost || err.code == .timedOut {
            throw ClientError.notRunning
        }
    }
}
