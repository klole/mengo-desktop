import XCTest
import SQLite3
@testable import MengoDesktop

private let SQLITE_TRANSIENT_BRIDGE = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Tests `MemoryDB` against a tiny deterministic fixture DB built fresh in
/// `setUp`. The schema is a minimal subset of screenpipe's — just the columns
/// our queries touch — so the test is robust to upstream schema additions.
///
/// Fixture contents (20 frames, 4 transcriptions, all within the last 30 min
/// so the time-window queries pick them up):
///
///   Chrome     id 1..10   1800s..900s ago   100s apart
///   VS Code    id 11..16  800s..300s ago    100s apart
///   Slack      id 17..20  200s..50s ago     50s apart
///
///   audio      id 1..4    700s, 500s, 300s, 100s ago
final class MemoryDBTests: XCTestCase {

    private var fixtureURL: URL!

    override func setUp() {
        super.setUp()
        fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("memory-db-\(UUID().uuidString).sqlite")
        seedFixture(at: fixtureURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: fixtureURL)
        super.tearDown()
    }

    // MARK: - topApps

    func test_topApps_returnsCountsDescendingWithinWindow() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let rows = try await db.topApps(window: 86_400, limit: 10)

        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.appName), ["Chrome", "Code", "Slack"])
        XCTAssertEqual(rows.map(\.frameCount), [10, 6, 4])
    }

    func test_topApps_appliesLimit() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let rows = try await db.topApps(window: 86_400, limit: 2)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.appName), ["Chrome", "Code"])
    }

    func test_topApps_emptyWhenWindowExcludesEverything() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let rows = try await db.topApps(window: 1, limit: 10) // 1-second window — too narrow
        XCTAssertEqual(rows.count, 0)
    }

    // MARK: - recentFrames

    func test_recentFrames_returnsAllInTimeOrder() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let frames = try await db.recentFrames(window: 86_400, limit: 100)

        XCTAssertEqual(frames.count, 20)
        // Ascending by timestamp — oldest first.
        for i in 1..<frames.count {
            XCTAssertLessThanOrEqual(frames[i - 1].timestamp, frames[i].timestamp)
        }
        // First 10 are Chrome, next 6 are Code, last 4 are Slack.
        XCTAssertEqual(frames.prefix(10).map(\.appName), Array(repeating: "Chrome", count: 10))
        XCTAssertEqual(frames.dropFirst(10).prefix(6).map(\.appName), Array(repeating: "Code", count: 6))
        XCTAssertEqual(frames.suffix(4).map(\.appName), Array(repeating: "Slack", count: 4))
    }

    // MARK: - recentActivity

    func test_recentActivity_emptyCursorReturnsAllNewestFirst() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let events = try await db.recentActivity(sinceFrameID: 0, sinceAudioID: 0, limit: 100)

        // 20 frames → 20 screenshots + 3 urlVisited (frames 1..3 have browser_url),
        // plus 4 transcriptions = 27 events.
        XCTAssertEqual(events.count, 27)
        // Newest-first.
        for i in 1..<events.count {
            XCTAssertGreaterThanOrEqual(events[i - 1].timestamp, events[i].timestamp)
        }
    }

    func test_recentActivity_cursorReturnsOnlyNew() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let events = try await db.recentActivity(sinceFrameID: 17, sinceAudioID: 3, limit: 100)

        // After id>17 on frames: only ids 18, 19, 20 (the last 3 Slack frames).
        // After id>3 on audio: only id 4.
        XCTAssertEqual(events.count, 4)
        let screenshotIDs: [Int64] = events.compactMap {
            if case .screenshot(let id, _, _, _) = $0 { return id } else { return nil }
        }
        let transcriptionIDs: [Int64] = events.compactMap {
            if case .transcription(let id, _, _) = $0 { return id } else { return nil }
        }
        XCTAssertEqual(Set(screenshotIDs), [18, 19, 20])
        XCTAssertEqual(Set(transcriptionIDs), [4])
    }

    func test_recentActivity_includesURLVisitedWhenBrowserURLPresent() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let events = try await db.recentActivity(sinceFrameID: 0, sinceAudioID: 0, limit: 100)

        // Frames 1..3 have browser_url set in the fixture — those should also emit .urlVisited.
        let urls: [String] = events.compactMap {
            if case .urlVisited(_, _, let url, _) = $0 { return url } else { return nil }
        }
        XCTAssertTrue(urls.contains("https://mail.google.com"))
    }

    // MARK: - last IDs

    func test_lastFrameID_returnsMax() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let last = try await db.lastFrameID()
        XCTAssertEqual(last, 20)
    }

    func test_lastAudioID_returnsMax() async throws {
        let db = MemoryDB(dbURL: fixtureURL)
        let last = try await db.lastAudioID()
        XCTAssertEqual(last, 4)
    }

    func test_lastFrameID_nilWhenEmpty() async throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("empty-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: empty) }
        seedSchema(at: empty)
        let db = MemoryDB(dbURL: empty)
        let last = try await db.lastFrameID()
        XCTAssertNil(last)
    }

    // MARK: - fixture builder

    private func seedSchema(at url: URL) {
        var conn: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &conn), SQLITE_OK)
        defer { sqlite3_close(conn) }
        let schema = """
            CREATE TABLE frames (
                id INTEGER PRIMARY KEY,
                timestamp TEXT NOT NULL,
                app_name TEXT,
                window_name TEXT,
                browser_url TEXT
            );
            CREATE TABLE audio_transcriptions (
                id INTEGER PRIMARY KEY,
                timestamp TEXT NOT NULL,
                transcription TEXT NOT NULL
            );
        """
        XCTAssertEqual(sqlite3_exec(conn, schema, nil, nil, nil), SQLITE_OK)
    }

    private func seedFixture(at url: URL) {
        seedSchema(at: url)

        var conn: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &conn), SQLITE_OK)
        defer { sqlite3_close(conn) }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let now = Date()
        func ts(_ secondsAgo: TimeInterval) -> String {
            iso.string(from: now.addingTimeInterval(-secondsAgo))
        }

        // 10 Chrome frames at 1800s..900s ago.
        var frames: [(Int, TimeInterval, String, String?, String?)] = []
        for i in 0..<10 {
            let secondsAgo = TimeInterval(1800 - i * 100)
            let url: String? = i < 3 ? "https://mail.google.com" : nil
            let win: String? = "Inbox"
            frames.append((i + 1, secondsAgo, "Chrome", win, url))
        }
        // 6 VS Code (Code) frames at 800s..300s ago.
        for i in 0..<6 {
            let secondsAgo = TimeInterval(800 - i * 100)
            frames.append((11 + i, secondsAgo, "Code", "MemoryDB.swift — MengoDesktop", nil))
        }
        // 4 Slack frames at 200s..50s ago.
        let slackOffsets: [TimeInterval] = [200, 150, 100, 50]
        for (i, offset) in slackOffsets.enumerated() {
            frames.append((17 + i, offset, "Slack", "#product-team", nil))
        }

        for (id, offset, app, win, url) in frames {
            let sql = """
                INSERT INTO frames (id, timestamp, app_name, window_name, browser_url)
                VALUES (?, ?, ?, ?, ?);
            """
            var stmt: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(conn, sql, -1, &stmt, nil), SQLITE_OK)
            sqlite3_bind_int64(stmt, 1, Int64(id))
            sqlite3_bind_text(stmt, 2, ts(offset), -1, SQLITE_TRANSIENT_BRIDGE)
            sqlite3_bind_text(stmt, 3, app, -1, SQLITE_TRANSIENT_BRIDGE)
            if let win { sqlite3_bind_text(stmt, 4, win, -1, SQLITE_TRANSIENT_BRIDGE) } else { sqlite3_bind_null(stmt, 4) }
            if let url { sqlite3_bind_text(stmt, 5, url, -1, SQLITE_TRANSIENT_BRIDGE) } else { sqlite3_bind_null(stmt, 5) }
            XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
            sqlite3_finalize(stmt)
        }

        // 4 transcriptions at 700, 500, 300, 100s ago.
        let transcripts: [(Int, TimeInterval, String)] = [
            (1, 700, "Discussing API rate limiting"),
            (2, 500, "Pair programming session on memory dashboard"),
            (3, 300, "Reviewing the new design with the team"),
            (4, 100, "Wrap up — let's ship the dashboard"),
        ]
        for (id, offset, text) in transcripts {
            let sql = "INSERT INTO audio_transcriptions (id, timestamp, transcription) VALUES (?, ?, ?);"
            var stmt: OpaquePointer?
            XCTAssertEqual(sqlite3_prepare_v2(conn, sql, -1, &stmt, nil), SQLITE_OK)
            sqlite3_bind_int64(stmt, 1, Int64(id))
            sqlite3_bind_text(stmt, 2, ts(offset), -1, SQLITE_TRANSIENT_BRIDGE)
            sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT_BRIDGE)
            XCTAssertEqual(sqlite3_step(stmt), SQLITE_DONE)
            sqlite3_finalize(stmt)
        }
    }
}
