import XCTest
@testable import ScreenpipeFlow

final class SynthesisRunnerTests: XCTestCase {

    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("synth-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmpDir)
    }

    /// Writes a small bash script that emulates `claude -p` for testing.
    private func writeFakeClaude(printingFinalLine line: String,
                                  exitCode: Int32 = 0) throws -> URL {
        let script = """
        #!/bin/bash
        echo "fake-claude started, args: $@"
        echo "some intermediate output"
        echo '\(line)'
        exit \(exitCode)
        """
        let url = tmpDir.appendingPathComponent("fake-claude.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: url.path)
        return url
    }

    func testParsesSuccessStatusLine() async throws {
        let claude = try writeFakeClaude(
            printingFinalLine: #"{"status":"ok","outputDir":"/tmp/skills/foo","slug":"foo"}"#)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: ["-p", "prompt", manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .success(let dir, let slug) = result {
            XCTAssertEqual(dir, URL(fileURLWithPath: "/tmp/skills/foo"))
            XCTAssertEqual(slug, "foo")
        } else {
            XCTFail("expected .success, got \(result)")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path))
    }

    func testParsesFailureStatusLine() async throws {
        let claude = try writeFakeClaude(
            printingFinalLine: #"{"status":"error","message":"no narration detected"}"#)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: [manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .failure(let msg) = result {
            XCTAssertTrue(msg.contains("no narration detected"))
        } else {
            XCTFail("expected .failure, got \(result)")
        }
    }

    func testFailsWhenNoStatusLineFound() async throws {
        let claude = try writeFakeClaude(printingFinalLine: "no json here")
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: [manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .failure = result { /* ok */ } else {
            XCTFail("expected .failure, got \(result)")
        }
    }

    func testFailsOnNonZeroExit() async throws {
        let claude = try writeFakeClaude(printingFinalLine: "anything", exitCode: 1)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let logURL = tmpDir.appendingPathComponent("synth.log")

        let result = try await SynthesisRunner.run(
            command: claude,
            arguments: [manifest.path],
            logFile: logURL,
            timeoutSeconds: 30
        )

        if case .failure = result { /* ok */ } else {
            XCTFail("expected .failure, got \(result)")
        }
    }

    func testParseLastStatusLineDirectly() {
        let stdout = """
        intermediate line
        another line
        {"status":"ok","outputDir":"/tmp/x","slug":"x"}
        """.data(using: .utf8)!
        let result = SynthesisRunner.parseLastStatusLine(stdout: stdout)
        if case .success(let dir, let slug) = result {
            XCTAssertEqual(dir.path, "/tmp/x")
            XCTAssertEqual(slug, "x")
        } else {
            XCTFail("expected .success")
        }
    }

    func testParseLastStatusLineHandlesTrailingTextAfterJSON() {
        // The walk-from-end logic should find the json on the second-to-last line.
        let stdout = """
        intermediate
        {"status":"ok","outputDir":"/tmp/x","slug":"x"}
        cleanup output
        """.data(using: .utf8)!
        let result = SynthesisRunner.parseLastStatusLine(stdout: stdout)
        if case .success = result { /* ok */ } else {
            XCTFail("expected .success even with trailing text")
        }
    }
}
