import XCTest
@testable import MengoDesktop

final class SkillFilesTests: XCTestCase {

    func test_parseSkillMarkdown_frontmatter() {
        let md = """
        ---
        name: staging-signups-report
        description: Pull today's signup count from the staging dashboard
          and post a one-line summary to Slack.
        ---

        # Staging Signups Report
        body here
        """
        let r = SkillFiles.parseSkillMarkdown(md)
        XCTAssertEqual(r.name, "staging-signups-report")
        XCTAssertEqual(r.description, "Pull today's signup count from the staging dashboard and post a one-line summary to Slack.")
        XCTAssertTrue(r.body.contains("# Staging Signups Report"))
        XCTAssertFalse(r.body.contains("name:"))
    }

    func test_parseSkillMarkdown_noFrontmatter() {
        let r = SkillFiles.parseSkillMarkdown("# Just a heading\ntext")
        XCTAssertNil(r.name); XCTAssertNil(r.description)
        XCTAssertEqual(r.body, "# Just a heading\ntext")
    }

    func test_parseFlowParameters_andSteps() {
        let json = Data("""
        { "schemaVersion": 1, "parameters": [
          { "name": "slack_channel", "description": "Channel to post to.", "default": "#growth", "autoDetected": false },
          { "name": "user_email", "exampleValue": "me@x.com", "autoDetected": true }
        ], "steps": [
          { "id": 1, "intent": "Open the dashboard", "inferred": true },
          { "id": 2, "intent": "Click Signups", "inferred": false }
        ] }
        """.utf8)
        let params = SkillFiles.parseFlowParameters(json)
        XCTAssertEqual(params.map(\.name), ["slack_channel", "user_email"])
        XCTAssertEqual(params[0].defaultValue, "#growth")
        XCTAssertFalse(params[0].autoDetected)
        XCTAssertEqual(params[1].defaultValue, "me@x.com")
        XCTAssertTrue(params[1].autoDetected)
        let steps = SkillFiles.parseFlowStepSummaries(json)
        XCTAssertEqual(steps, ["1. Open the dashboard  (inferred — verify)", "2. Click Signups"])
    }

    func test_parseFlow_garbage_returnsEmpty() {
        XCTAssertEqual(SkillFiles.parseFlowParameters(Data("nope".utf8)).count, 0)
        XCTAssertEqual(SkillFiles.parseFlowStepSummaries(Data("nope".utf8)).count, 0)
    }
}
