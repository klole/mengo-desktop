import Foundation

/// screenpipe's `/health` response — the subset Mengo Memory surfaces. screenpipe
/// includes more; unknown keys are ignored, and any field a build omits is `nil`.
/// `lastFrameTimestamp` is kept as a raw string and parsed leniently by the UI so a
/// malformed value can't fail the whole decode.
struct ScreenpipeHealth: Decodable, Sendable {
    var status: String
    var frameStatus: String
    var audioStatus: String
    var version: String? = nil
    var monitors: [String]? = nil
    var lastFrameTimestamp: String? = nil
    var pipeline: Pipeline? = nil
    var audioPipeline: AudioPipeline? = nil

    struct Pipeline: Decodable, Sendable {
        var uptimeSecs: Double? = nil
        var framesCaptured: Int? = nil
        private enum CodingKeys: String, CodingKey {
            case uptimeSecs = "uptime_secs"
            case framesCaptured = "frames_captured"
        }
    }

    struct AudioPipeline: Decodable, Sendable {
        var totalWords: Int? = nil
        var audioDevices: [String]? = nil
        private enum CodingKeys: String, CodingKey {
            case totalWords = "total_words"
            case audioDevices = "audio_devices"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case status, version, monitors, pipeline
        case frameStatus = "frame_status"
        case audioStatus = "audio_status"
        case lastFrameTimestamp = "last_frame_timestamp"
        case audioPipeline = "audio_pipeline"
    }
}

/// The screenpipe HTTP operations `RecorderController` depends on.
protocol RecorderHealthAPI: Sendable {
    func health() async throws -> ScreenpipeHealth
    func audioStart() async throws
    func audioStop() async throws
}

/// Thin client over screenpipe's local HTTP API. Ported from V1's
/// `ScreenpipeMenu/APIClient.swift`.
actor APIClient: RecorderHealthAPI {
    private let baseURL = URL(string: "http://127.0.0.1:3030")!
    private let token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    /// Exposed for tests.
    var baseURLForTesting: URL { baseURL }

    enum APIError: Error {
        case badStatus(Int)
        case noResponse
    }

    func health() async throws -> ScreenpipeHealth {
        try await get("/health", as: ScreenpipeHealth.self)
    }

    func audioStop() async throws { try await post("/audio/stop") }
    func audioStart() async throws { try await post("/audio/start") }

    private func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: req)
        try check(response)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post(_ path: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await session.data(for: req)
        try check(response)
    }

    private func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw APIError.noResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
    }
}
