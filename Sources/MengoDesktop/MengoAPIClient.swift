import Foundation

enum Plan: String, Codable, Equatable { case free, pro }

/// The user's Mengo account snapshot. `flowLimit == nil` ⇒ unlimited (Pro).
struct Account: Codable, Equatable {
    let email: String
    let plan: Plan
    let flowLimit: Int?       // decoded; nil if absent or null
    var validatedAt: Date = .init()   // set locally on each successful fetch; not from the server

    private enum CodingKeys: String, CodingKey { case email, plan, flowLimit, validatedAt }
    init(email: String, plan: Plan, flowLimit: Int?, validatedAt: Date = .init()) {
        self.email = email; self.plan = plan; self.flowLimit = flowLimit; self.validatedAt = validatedAt
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        email = try c.decode(String.self, forKey: .email)
        plan = try c.decode(Plan.self, forKey: .plan)
        flowLimit = try c.decodeIfPresent(Int.self, forKey: .flowLimit) ?? nil
        validatedAt = try c.decodeIfPresent(Date.self, forKey: .validatedAt) ?? Date()
    }
}

struct ExchangeResponse: Decodable { let sessionToken: String; let account: Account }

/// HTTPS operations against `mengo.ai`. (The website owner builds these endpoints.)
protocol MengoAPI: Sendable {
    func requestLink(email: String) async throws
    func exchange(token: String) async throws -> ExchangeResponse
    func me(sessionToken: String) async throws -> Account
    func webHandoff(sessionToken: String) async throws -> String
}

enum MengoAPIError: Error, LocalizedError, Equatable {
    case unauthorized, notReachable, badStatus(Int), badBody
    var errorDescription: String? {
        switch self {
        case .unauthorized:    return "your session has expired — sign in again"
        case .notReachable:    return "couldn't reach mengo.ai — check your connection"
        case .badStatus(let c):return "mengo.ai returned HTTP \(c)"
        case .badBody:         return "mengo.ai sent an unexpected response"
        }
    }
}

struct MengoAPIClient: MengoAPI {
    var baseURL = MengoAPIClient.defaultBaseURL()
    var urlSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral; c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    /// `MENGO_API_BASE` overrides this so a dev build can talk to `http://localhost:3000`
    /// without rebuilding. Production launches always hit `https://mengo.ai`.
    static func defaultBaseURL() -> URL {
        if let override = ProcessInfo.processInfo.environment["MENGO_API_BASE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           let url = URL(string: override) {
            return url
        }
        return URL(string: "https://mengo.ai")!
    }

    func requestLink(email: String) async throws {
        _ = try await postJSON("/api/auth/request-link", body: ["email": email], bearer: nil)
    }
    func exchange(token: String) async throws -> ExchangeResponse {
        let data = try await postJSON("/api/auth/exchange", body: ["token": token], bearer: nil)
        return try Self.decodeExchange(data)
    }
    func me(sessionToken: String) async throws -> Account {
        let data = try await get("/api/me", bearer: sessionToken)
        return try Self.decodeAccount(data)
    }
    func webHandoff(sessionToken: String) async throws -> String {
        let data = try await postJSON("/api/auth/web-handoff", body: [:], bearer: sessionToken)
        guard let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["handoffCode"] as? String
        else { throw MengoAPIError.badBody }
        return code
    }

    // MARK: pure decoders (tested)
    static func decodeExchange(_ data: Data) throws -> ExchangeResponse {
        do { return try JSONDecoder().decode(ExchangeResponse.self, from: data) } catch { throw MengoAPIError.badBody }
    }
    static func decodeAccount(_ data: Data) throws -> Account {
        do { return try JSONDecoder().decode(Account.self, from: data) } catch { throw MengoAPIError.badBody }
    }

    // MARK: transport
    private func get(_ path: String, bearer: String?) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        return try await send(req)
    }
    private func postJSON(_ path: String, body: [String: Any], bearer: String?) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let bearer { req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await send(req)
    }
    private func send(_ req: URLRequest) async throws -> Data {
        let data: Data, response: URLResponse
        do { (data, response) = try await urlSession.data(for: req) }
        catch { throw MengoAPIError.notReachable }
        guard let http = response as? HTTPURLResponse else { throw MengoAPIError.notReachable }
        if http.statusCode == 401 { throw MengoAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw MengoAPIError.badStatus(http.statusCode) }
        return data
    }
}
