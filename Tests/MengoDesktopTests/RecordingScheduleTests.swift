import XCTest
@testable import MengoDesktop

/// Direct unit tests for `RecordingScheduleRule.contains` — the wrap-midnight
/// + weekday-boundary logic isn't covered by the integration-style tests in
/// `RecorderControllerTests`, and it's the trickiest part of the schedule
/// model.
final class RecordingScheduleTests: XCTestCase {

    private let calendar = Calendar(identifier: .gregorian)

    // MARK: - Helpers

    private func date(weekday: Weekday, hour: Int, minute: Int) -> Date {
        var comps = DateComponents()
        comps.weekday = weekday.rawValue
        comps.hour = hour
        comps.minute = minute
        // Anchor to a deterministic ISO week — any week works.
        comps.yearForWeekOfYear = 2026
        comps.weekOfYear = 10
        return calendar.date(from: comps) ?? Date()
    }

    private func recurring(days: Set<Weekday>, start: ClockTime, end: ClockTime) -> RecordingScheduleRule {
        .recurring(id: UUID(), days: days, start: start, end: end)
    }

    // MARK: - Same-day rules

    func test_recurring_sameDayWindow_isActiveInsideWindow() {
        let rule = recurring(days: [.mon], start: ClockTime(hour: 9, minute: 0), end: ClockTime(hour: 17, minute: 0))
        XCTAssertTrue(rule.contains(date(weekday: .mon, hour: 12, minute: 0), calendar: calendar))
        XCTAssertTrue(rule.contains(date(weekday: .mon, hour: 9,  minute: 0), calendar: calendar))   // inclusive start
        XCTAssertFalse(rule.contains(date(weekday: .mon, hour: 17, minute: 0), calendar: calendar))  // exclusive end
        XCTAssertFalse(rule.contains(date(weekday: .mon, hour: 8,  minute: 59), calendar: calendar)) // before start
    }

    func test_recurring_otherWeekday_isInactive() {
        let rule = recurring(days: [.mon], start: ClockTime(hour: 9, minute: 0), end: ClockTime(hour: 17, minute: 0))
        XCTAssertFalse(rule.contains(date(weekday: .tue, hour: 12, minute: 0), calendar: calendar))
        XCTAssertFalse(rule.contains(date(weekday: .sun, hour: 12, minute: 0), calendar: calendar))
    }

    // MARK: - Wrap-midnight rules

    func test_recurring_wrap_activeEveningOfRuleDay() {
        // Sunday 22:00 → 06:00 (Monday morning).
        let rule = recurring(days: [.sun], start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 6, minute: 0))
        XCTAssertTrue(rule.contains(date(weekday: .sun, hour: 22, minute: 0), calendar: calendar))
        XCTAssertTrue(rule.contains(date(weekday: .sun, hour: 23, minute: 30), calendar: calendar))
    }

    func test_recurring_wrap_activeMorningAfterIntoNextWeekday() {
        // The whole point of this test: at Monday 03:00, the Sunday rule
        // should still be considered active because we're in the morning-
        // after half of yesterday's window.
        let rule = recurring(days: [.sun], start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 6, minute: 0))
        XCTAssertTrue(rule.contains(date(weekday: .mon, hour: 3,  minute: 0),  calendar: calendar),
                      "Sun 22:00→06:00 should still be active on Mon 03:00")
        XCTAssertTrue(rule.contains(date(weekday: .mon, hour: 5,  minute: 59), calendar: calendar))
        XCTAssertFalse(rule.contains(date(weekday: .mon, hour: 6,  minute: 0),  calendar: calendar),
                       "exclusive at the end")
        XCTAssertFalse(rule.contains(date(weekday: .mon, hour: 12, minute: 0),  calendar: calendar),
                       "well past the wrap window")
    }

    func test_recurring_wrap_inactiveBeforeStartOnRuleDay() {
        let rule = recurring(days: [.sun], start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 6, minute: 0))
        XCTAssertFalse(rule.contains(date(weekday: .sun, hour: 21, minute: 59), calendar: calendar))
    }

    func test_recurring_wrap_inactiveOnNonRuleDayAtSameClock() {
        // A Sunday wrap rule shouldn't fire on Saturday night just because
        // the clock matches.
        let rule = recurring(days: [.sun], start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 6, minute: 0))
        XCTAssertFalse(rule.contains(date(weekday: .sat, hour: 23, minute: 0), calendar: calendar))
        // Tuesday morning shouldn't either (Monday isn't in the rule).
        XCTAssertFalse(rule.contains(date(weekday: .tue, hour: 3, minute: 0), calendar: calendar))
    }

    // MARK: - One-off

    func test_oneOff_activeWithinRange() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        let end   = start.addingTimeInterval(3600)
        let rule: RecordingScheduleRule = .oneOff(id: UUID(), start: start, end: end)
        XCTAssertTrue(rule.contains(start.addingTimeInterval(1)))
        XCTAssertTrue(rule.contains(start))                                   // inclusive start
        XCTAssertFalse(rule.contains(end))                                    // exclusive end
        XCTAssertFalse(rule.contains(start.addingTimeInterval(-1)))           // before
        XCTAssertFalse(rule.contains(end.addingTimeInterval(1)))              // after
    }

    // MARK: - Schedule (multi-rule)

    func test_schedule_isActive_anyRuleMatch() {
        let r1 = recurring(days: [.mon], start: ClockTime(hour: 9, minute: 0), end: ClockTime(hour: 12, minute: 0))
        let r2 = recurring(days: [.tue], start: ClockTime(hour: 9, minute: 0), end: ClockTime(hour: 12, minute: 0))
        let schedule = RecordingSchedule(rules: [r1, r2])
        XCTAssertTrue(schedule.isActive(at: date(weekday: .mon, hour: 10, minute: 0), calendar: calendar))
        XCTAssertTrue(schedule.isActive(at: date(weekday: .tue, hour: 10, minute: 0), calendar: calendar))
        XCTAssertFalse(schedule.isActive(at: date(weekday: .wed, hour: 10, minute: 0), calendar: calendar))
    }

    func test_schedule_empty_isAlwaysInactive() {
        XCTAssertFalse(RecordingSchedule.empty.isActive(at: Date()))
    }
}
