import Foundation

/// One moment from screenpipe's recent capture — used by the "grab last N minutes"
/// picker. Carries enough to recognise *when* a task started without fetching an image.
struct Moment: Equatable, Hashable, Identifiable {
    let timestamp: Date
    let appName: String
    let windowName: String
    var id: Date { timestamp }
}

/// Abstracts the screenpipe `/search` query so `FlowController` tests can stub it.
protocol MomentIndexing: Sendable {
    func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment]
}

/// A no-op `MomentIndexing` — the default in `FlowController.init` when no real
/// recorder token is available (production wires a `ScreenpipeSearchClient` via `live(…)`).
struct NullMomentIndexing: MomentIndexing {
    func momentIndex(from: Date, to: Date, limit: Int) async throws -> [Moment] { [] }
}

/// Queries screenpipe's local HTTP API (`GET /search?content_type=ocr`) for a
/// decimated list of recent moments, authed with the recorder's per-launch token.
/// (Mirrors V1's `ScreenpipeClient.thumbnailIndex`, minus the `auth token` discovery
/// — V2's token comes from `RecorderController.screenpipeToken`.)
struct ScreenpipeSearchClient: MomentIndexing {
    let token: String
    var baseURL = URL(string: "http://127.0.0.1:3030")!
    var urlSession: URLSession = .shared
    var decimateIntervalSec: TimeInterval = 15

    enum SearchError: Error, LocalizedError {
        case notResponding, http(Int)
        var errorDescription: String? {
            switch self {
            case .notResponding: return "the recorder isn't responding"
            case .http(let c):   return "the recorder returned HTTP \(c)"
            }
        }
    }

    func momentIndex(from start: Date, to end: Date, limit: Int) async throws -> [Moment] {
        var comps = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "content_type", value: "ocr"),
            .init(name: "start_time", value: Self.iso.string(from: start)),
            .init(name: "end_time", value: Self.iso.string(from: end)),
            .init(name: "limit", value: String(limit)),
        ]
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 10
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await urlSession.data(for: req) }
        catch let e as URLError where e.code == .cannotConnectToHost || e.code == .timedOut { throw SearchError.notResponding }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw SearchError.http(http.statusCode) }
        return Self.decimate(Self.parseMomentIndex(data), minIntervalSec: decimateIntervalSec)
    }

    // MARK: pure helpers (tested directly)

    static func parseMomentIndex(_ data: Data) -> [Moment] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = json["data"] as? [[String: Any]] else { return [] }
        var out: [Moment] = []
        for row in rows {
            guard ((row["type"] as? String)?.lowercased() == "ocr"),
                  let content = row["content"] as? [String: Any],
                  let ts = content["timestamp"] as? String,
                  let date = MemoryFormatting.parseTimestamp(ts) else { continue }
            out.append(Moment(timestamp: date,
                              appName: (content["app_name"] as? String) ?? "",
                              windowName: (content["window_name"] as? String) ?? ""))
        }
        return out.sorted { $0.timestamp < $1.timestamp }
    }

    /// Keeps at most one moment per `minIntervalSec` (walking oldest→newest).
    static func decimate(_ moments: [Moment], minIntervalSec: TimeInterval) -> [Moment] {
        var last: Date?
        var out: [Moment] = []
        for m in moments.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let l = last, m.timestamp.timeIntervalSince(l) < minIntervalSec { continue }
            out.append(m); last = m.timestamp
        }
        return out
    }

    private static var iso: ISO8601DateFormatter {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }
}
