import XCTest
@testable import ScreenpipeFlow

final class SlugTests: XCTestCase {

    func testKebabCaseFromTitle() {
        XCTAssertEqual(Slug.derive(from: "Staging Signups Report"), "staging-signups-report")
    }

    func testStripsPunctuationAndCollapsesSpaces() {
        XCTAssertEqual(Slug.derive(from: "Hello, World!  Foo--bar"), "hello-world-foo-bar")
    }

    func testLeadingTrailingDashesRemoved() {
        XCTAssertEqual(Slug.derive(from: "  --weird-- "), "weird")
    }

    func testEmptyOrAllPunctuationFallsBackToDefault() {
        XCTAssertEqual(Slug.derive(from: ""), "untitled-flow")
        XCTAssertEqual(Slug.derive(from: "!!!"), "untitled-flow")
    }

    func testLongInputTruncatedTo60Chars() {
        let long = String(repeating: "a", count: 200)
        let slug = Slug.derive(from: long)
        XCTAssertLessThanOrEqual(slug.count, 60)
    }

    func testUniquifyAppendsSuffixWhenCollision() {
        let existing: Set<String> = ["check-prs", "check-prs-2"]
        XCTAssertEqual(Slug.uniquify("check-prs", existing: existing), "check-prs-3")
    }

    func testUniquifyReturnsOriginalWhenNoCollision() {
        XCTAssertEqual(Slug.uniquify("brand-new", existing: ["other"]), "brand-new")
    }
}
