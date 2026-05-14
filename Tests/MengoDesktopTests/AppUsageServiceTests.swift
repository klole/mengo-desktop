import XCTest
@testable import MengoDesktop

final class AppUsageServiceTests: XCTestCase {

    func test_rows_percentSumsTo100() {
        let raw = [
            RawAppCount(appName: "Chrome", frameCount: 10),
            RawAppCount(appName: "Code", frameCount: 6),
            RawAppCount(appName: "Slack", frameCount: 4),
        ]
        let rows = AppUsageService.rows(from: raw)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows.map(\.sharePercent), [50, 30, 20])
        XCTAssertEqual(rows.reduce(0) { $0 + $1.sharePercent }, 100)
    }

    func test_rows_percentRoundedToInteger() {
        // 1 / 3 frames each → 33 / 33 / 33 = 99; off-by-one is acceptable.
        let raw = [
            RawAppCount(appName: "Chrome", frameCount: 1),
            RawAppCount(appName: "Code", frameCount: 1),
            RawAppCount(appName: "Slack", frameCount: 1),
        ]
        let rows = AppUsageService.rows(from: raw)
        let sum = rows.reduce(0) { $0 + $1.sharePercent }
        XCTAssertTrue((99...100).contains(sum), "Expected sum near 100, got \(sum)")
    }

    func test_rows_emptyInputReturnsEmpty() {
        XCTAssertEqual(AppUsageService.rows(from: []), [])
    }

    func test_displayName_mapsKnownApps() {
        XCTAssertEqual(AppUsageService.displayName(for: "Chrome"), "Google Chrome")
        XCTAssertEqual(AppUsageService.displayName(for: "Google Chrome"), "Google Chrome")
        XCTAssertEqual(AppUsageService.displayName(for: "Code"), "VS Code")
        XCTAssertEqual(AppUsageService.displayName(for: "Visual Studio Code"), "VS Code")
        XCTAssertEqual(AppUsageService.displayName(for: "Slack"), "Slack")
        XCTAssertEqual(AppUsageService.displayName(for: "Figma"), "Figma")
    }

    func test_displayName_unknownAppPassthrough() {
        XCTAssertEqual(AppUsageService.displayName(for: "Cattaclysm"), "Cattaclysm")
    }

    func test_iconName_mapsKnownApps_unknownFallsBackToDashed() {
        XCTAssertEqual(AppUsageService.iconName(for: "Chrome"), "globe")
        XCTAssertEqual(AppUsageService.iconName(for: "Code"), "chevron.left.forwardslash.chevron.right")
        XCTAssertEqual(AppUsageService.iconName(for: "Slack"), "number")
        XCTAssertEqual(AppUsageService.iconName(for: "Cattaclysm"), "square.dashed")
    }
}
