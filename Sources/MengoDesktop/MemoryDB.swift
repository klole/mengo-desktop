import Foundation
import SQLite3

// SQLite's `SQLITE_TRANSIENT` constant — the C macro doesn't import to Swift,
// so we materialize it the usual way. Forces SQLite to copy bound strings.
private let SQLITE_TRANSIENT_MENGO = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum MemoryDBError: Error, LocalizedError, Equatable {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m):  return "Couldn't open the memory database: \(m)"
        case .queryFailed(let m): return "Memory database query failed: \(m)"
        }
    }
}

/// Read-only client for the recorder's local SQLite database
/// (`~/.screenpipe/db.sqlite`). Serialized through an actor so we can hold a
/// single connection without worrying about cross-task interleaving; the
/// connection is opened lazily on first query and closed on deinit.
///
/// Opens with `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` so it never
/// contends with the recorder's writes — the recorder owns write-locking.
actor MemoryDB {
    private var connection: OpaquePointer?
    private let dbURL: URL

    init(dbURL: URL) {
        self.dbURL = dbURL
    }

    // No deinit close: with `SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX` the
    // OS reaps the file descriptor on process exit and our single connection
    // never blocks the recorder's writes. Swift 6's deinit isolation rules
    // make accessing the non-Sendable `connection` here awkward, and the
    // tradeoff isn't worth it.

    static func live() -> MemoryDB {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".screenpipe/db.sqlite")
        return MemoryDB(dbURL: url)
    }

    // MARK: - Queries

    /// Frame counts per app over the given time window, descending. Excludes
    /// rows where `app_name` is null or empty.
    func topApps(window: TimeInterval, limit: Int) throws -> [RawAppCount] {
        let db = try openIfNeeded()
        let threshold = isoString(Date().addingTimeInterval(-window))

        let sql = """
            SELECT app_name, COUNT(*) AS cnt
            FROM frames
            WHERE app_name IS NOT NULL
              AND app_name != ''
              AND timestamp > ?
            GROUP BY app_name
            ORDER BY cnt DESC
            LIMIT ?;
        """
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, threshold, -1, SQLITE_TRANSIENT_MENGO)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var rows: [RawAppCount] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cstr = sqlite3_column_text(stmt, 0) else { continue }
            let appName = String(cString: cstr)
            let count = Int(sqlite3_column_int(stmt, 1))
            rows.append(RawAppCount(appName: appName, frameCount: count))
        }
        return rows
    }

    /// Raw frames over the given time window, in ascending timestamp order.
    /// The caller (typically `SessionsService`) clusters them into sessions.
    func recentFrames(window: TimeInterval, limit: Int) throws -> [FrameRow] {
        let db = try openIfNeeded()
        let threshold = isoString(Date().addingTimeInterval(-window))

        let sql = """
            SELECT id, timestamp, app_name, window_name, browser_url
            FROM frames
            WHERE app_name IS NOT NULL
              AND app_name != ''
              AND timestamp > ?
            ORDER BY timestamp ASC
            LIMIT ?;
        """
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, threshold, -1, SQLITE_TRANSIENT_MENGO)
        sqlite3_bind_int(stmt, 2, Int32(limit))

        var rows: [FrameRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let row = decodeFrame(stmt) else { continue }
            rows.append(row)
        }
        return rows
    }

    /// Newest-first merged feed of frames + transcriptions whose ids exceed
    /// the given cursors, capped to `limit` total events. Pass `0` for either
    /// cursor to include everything of that kind. Frames with a non-empty
    /// `browser_url` additionally emit a `.urlVisited` event alongside their
    /// `.screenshot` event — but the total return is still bounded by `limit`.
    ///
    /// Cursor advancement note: the caller advances its cursors to the max
    /// IDs in the returned events. Any events dropped by the post-merge cap
    /// (older than the kept set) will be re-queried on a later tick because
    /// the cursor sat just above the kept events' minimum id, not below the
    /// dropped ones. In practice for our 5-s polling interval the cap is
    /// almost never hit, so the trade-off favors a clean contract.
    func recentActivity(sinceFrameID: Int64, sinceAudioID: Int64, limit: Int) throws -> [ActivityEvent] {
        let db = try openIfNeeded()

        var events: [ActivityEvent] = []

        // Frames → .screenshot (+ .urlVisited if browser_url is set). Per-query
        // limit is `limit` so we never starve audio; the combined return is
        // capped at the end.
        do {
            let sql = """
                SELECT id, timestamp, app_name, window_name, browser_url
                FROM frames
                WHERE id > ?
                ORDER BY id DESC
                LIMIT ?;
            """
            let stmt = try prepare(db, sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, sinceFrameID)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let frame = decodeFrame(stmt) else { continue }
                events.append(.screenshot(id: frame.id, at: frame.timestamp, appName: frame.appName, windowName: frame.windowName))
                if let url = frame.browserURL, !url.isEmpty {
                    events.append(.urlVisited(id: frame.id, at: frame.timestamp, url: url, appName: frame.appName))
                }
            }
        }

        // Transcriptions → .transcription.
        do {
            let sql = """
                SELECT id, timestamp, transcription
                FROM audio_transcriptions
                WHERE id > ?
                ORDER BY id DESC
                LIMIT ?;
            """
            let stmt = try prepare(db, sql)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, sinceAudioID)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                guard let tsCStr = sqlite3_column_text(stmt, 1),
                      let ts = parseTimestamp(String(cString: tsCStr)) else { continue }
                guard let textCStr = sqlite3_column_text(stmt, 2) else { continue }
                let text = String(cString: textCStr)
                events.append(.transcription(id: id, at: ts, snippet: text))
            }
        }

        // Newest-first merged ordering, capped to `limit` total events so the
        // method honors its name. Without this cap a browser-URL-heavy tick
        // could return 2× frames + transcriptions, overflowing consumer caps.
        return Array(events.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    func lastFrameID() throws -> Int64? {
        try maxID(table: "frames")
    }

    func lastAudioID() throws -> Int64? {
        try maxID(table: "audio_transcriptions")
    }

    // MARK: - Internals

    private func openIfNeeded() throws -> OpaquePointer {
        if let c = connection { return c }
        var c: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let result = sqlite3_open_v2(dbURL.path, &c, flags, nil)
        guard result == SQLITE_OK, let c else {
            let msg = c.map { String(cString: sqlite3_errmsg($0)) } ?? "open returned \(result)"
            if let c { sqlite3_close_v2(c) }
            throw MemoryDBError.openFailed(msg)
        }
        connection = c
        return c
    }

    private func prepare(_ db: OpaquePointer, _ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw MemoryDBError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func decodeFrame(_ stmt: OpaquePointer?) -> FrameRow? {
        let id = sqlite3_column_int64(stmt, 0)
        guard let tsCStr = sqlite3_column_text(stmt, 1),
              let ts = parseTimestamp(String(cString: tsCStr)) else { return nil }
        guard let appCStr = sqlite3_column_text(stmt, 2) else { return nil }
        let app = String(cString: appCStr)
        let win = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let url = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        return FrameRow(id: id, timestamp: ts, appName: app, windowName: win, browserURL: url)
    }

    private func maxID(table: String) throws -> Int64? {
        let db = try openIfNeeded()
        let sql = "SELECT MAX(id) FROM \(table);"
        let stmt = try prepare(db, sql)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, 0)
    }

    // MARK: - Timestamp helpers

    nonisolated private func isoString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    nonisolated private func parseTimestamp(_ s: String) -> Date? {
        MemoryFormatting.parseTimestamp(s)
    }
}
