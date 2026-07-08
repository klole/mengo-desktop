import XCTest
@testable import MengoDesktop

@MainActor
final class ManifestWriterTests: XCTestCase {

    nonisolated(unsafe) var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("manifest-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    func testProactiveManifestStructure() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: start, endTime: nil)
        session.endTime = start.addingTimeInterval(60)

        let manifestURL = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/Users/test/.claude/skills"),
            userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
            regenerationContext: nil, manifestsDir: tmpDir)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        XCTAssertEqual(json["manifestVersion"] as? Int, 1)
        XCTAssertEqual(json["mode"] as? String, "proactive")
        XCTAssertNotNil(json["manifestId"])
        XCTAssertEqual(json["outputDir"] as? String, "/Users/test/.claude/skills")
        XCTAssertTrue(json["regenerationContext"] is NSNull)
        let timeRange = json["timeRange"] as? [String: Any]
        XCTAssertEqual(timeRange?["start"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(timeRange?["end"] as? String, "2023-11-14T22:14:20Z")
        XCTAssertEqual(json["activeRecordingStart"] as? String, "2023-11-14T22:13:20Z")
    }

    func testRetroactiveManifestHasBufferStart() throws {
        let bufferStart = Date(timeIntervalSince1970: 1_700_000_000)
        let activeStart = bufferStart.addingTimeInterval(300)
        var session = FlowSession(mode: .retroactive, bufferRangeStart: bufferStart, activeRecordingStart: activeStart, endTime: nil)
        session.endTime = activeStart.addingTimeInterval(60)

        let manifestURL = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/Users/test/.claude/skills"),
            userHintsName: "Weekly Report", userHintsDescription: nil, userHintsNotes: nil,
            regenerationContext: nil, manifestsDir: tmpDir)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        XCTAssertEqual(json["mode"] as? String, "retroactive")
        let timeRange = json["timeRange"] as? [String: Any]
        XCTAssertEqual(timeRange?["start"] as? String, "2023-11-14T22:13:20Z")
        XCTAssertEqual(json["activeRecordingStart"] as? String, "2023-11-14T22:18:20Z")
        let hints = json["userHints"] as? [String: Any]
        XCTAssertEqual(hints?["name"] as? String, "Weekly Report")
    }

    func testRegenerationContextSerializes() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: start, endTime: nil)
        session.endTime = start.addingTimeInterval(30)

        let regen = ManifestWriter.RegenerationContext(
            previousSkillPath: URL(fileURLWithPath: "/Users/test/.claude/skills/foo"),
            userFeedback: "Rename it to bar")

        let manifestURL = try ManifestWriter.write(
            session: session,
            outputDir: URL(fileURLWithPath: "/Users/test/.claude/skills"),
            userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
            regenerationContext: regen, manifestsDir: tmpDir)

        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as! [String: Any]
        let ctx = json["regenerationContext"] as? [String: Any]
        XCTAssertEqual(ctx?["previousSkillPath"] as? String, "/Users/test/.claude/skills/foo")
        XCTAssertEqual(ctx?["userFeedback"] as? String, "Rename it to bar")
    }

    func testNilUserHintsSerializeAsJSONNull() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: start, endTime: nil)
        session.endTime = start.addingTimeInterval(20)

        let url = try ManifestWriter.write(
            session: session, outputDir: URL(fileURLWithPath: "/x"),
            userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
            regenerationContext: nil, manifestsDir: tmpDir)
        let raw = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"name\" : null"))
        XCTAssertTrue(raw.contains("\"description\" : null"))
        XCTAssertTrue(raw.contains("\"notes\" : null"))
        let json = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
        let hints = json["userHints"] as! [String: Any]
        XCTAssertTrue(hints["name"] is NSNull)
        XCTAssertTrue(hints["description"] is NSNull)
        XCTAssertTrue(hints["notes"] is NSNull)
    }

    func testManifestFilenameIsUUIDJson() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var session = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: start, endTime: nil)
        session.endTime = start.addingTimeInterval(10)
        let url = try ManifestWriter.write(
            session: session, outputDir: URL(fileURLWithPath: "/x"),
            userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
            regenerationContext: nil, manifestsDir: tmpDir)
        XCTAssertEqual(url.pathExtension, "json")
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent.count, 36)
    }
}
