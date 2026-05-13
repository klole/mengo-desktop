import XCTest
@testable import MengoDesktop

final class MemoryFormattingTests: XCTestCase {

    func test_bytes_scalesWithMagnitude() {
        XCTAssertFalse(MemoryFormatting.bytes(0).isEmpty)
        XCTAssertTrue(MemoryFormatting.bytes(1_500).contains("KB"))
        XCTAssertTrue(MemoryFormatting.bytes(5_000_000).contains("MB"))
        XCTAssertTrue(MemoryFormatting.bytes(3_200_000_000).contains("GB"))
    }

    func test_duration_abbreviates() {
        XCTAssertEqual(MemoryFormatting.duration(seconds: 0), "0s")
        XCTAssertEqual(MemoryFormatting.duration(seconds: 5), "5s")
        XCTAssertEqual(MemoryFormatting.duration(seconds: 257), "4m 17s")
        XCTAssertEqual(MemoryFormatting.duration(seconds: 8040), "2h 14m")
    }

    func test_relative_recentIsJustNow_olderCountsMinutes() {
        let now = Date()
        XCTAssertEqual(MemoryFormatting.relative(from: now.addingTimeInterval(-10), now: now), "just now")
        XCTAssertEqual(MemoryFormatting.relative(from: now.addingTimeInterval(-120), now: now), "2 minutes ago")
        XCTAssertEqual(MemoryFormatting.relative(from: now.addingTimeInterval(-60), now: now), "1 minute ago")
    }

    func test_relative_oldFallsBackToClockTime() {
        let now = Date()
        let old = now.addingTimeInterval(-3 * 3600)   // 3 h ago
        let s = MemoryFormatting.relative(from: old, now: now)
        XCTAssertFalse(s.contains("ago"))             // a clock time like "3:14 PM", not "3 hours ago"
        XCTAssertFalse(s.isEmpty)
    }

    func test_parseTimestamp_handlesOffsetAndZAndFractional_andRejectsGarbage() {
        XCTAssertNotNil(MemoryFormatting.parseTimestamp("2026-05-12T18:31:18-06:00"))
        XCTAssertNotNil(MemoryFormatting.parseTimestamp("2026-05-12T19:04:58Z"))
        XCTAssertNotNil(MemoryFormatting.parseTimestamp("2026-05-12T19:04:58.000Z"))
        XCTAssertNil(MemoryFormatting.parseTimestamp("not a date"))
        XCTAssertNil(MemoryFormatting.parseTimestamp(""))
    }
}
