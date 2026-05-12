import Foundation

actor APIClient {
    private let baseURL = URL(string: "http://127.0.0.1:3030")!
    private let token: String
    private let session: URLSession

    init(token: String) {
        self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        self.session = URLSession(configuration: config)
    }

    struct HealthStatus: Decodable, Sendable {
        let status: String
        let frame_status: String
        let audio_status: String
    }

    enum APIError: Error {
        case badStatus(Int)
        case noResponse
    }

    func health() async throws -> HealthStatus {
        try await get("/health", as: HealthStatus.self)
    }

    func audioStop() async throws {
        try await post("/audio/stop")
    }

    func audioStart() async throws {
        try await post("/audio/start")
    }

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
