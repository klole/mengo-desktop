import XCTest
@testable import MengoDesktop

final class SynthesisRunnerTests: XCTestCase {

    var tmpDir: URL!

    override func setUpWithError() throws {
        tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("synth-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmpDir) }

    private func writeFakeClaude(printingFinalLine line: String, exitCode: Int32 = 0) throws -> URL {
        let script = """
        #!/bin/bash
        echo "fake-claude started, args: $@"
        echo "some intermediate output"
        echo '\(line)'
        exit \(exitCode)
        """
        let url = tmpDir.appendingPathComponent("fake-claude.sh")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func testParsesSuccessStatusLine() async throws {
        let claude = try writeFakeClaude(printingFinalLine: #"{"status":"ok","outputDir":"/tmp/skills/foo","slug":"foo"}"#)
        let manifest = tmpDir.appendingPathComponent("manifest.json")
        try "{}".write(to: manifest, atomically: true, encoding: .utf8)
        let result = try await SynthesisRunner.run(command: claude, arguments: ["-p", "prompt", manifest.path],
                                                   environment: nil, logFile: tmpDir.appendingPathComponent("synth.log"), timeoutSeconds: 30)
        if case .success(let dir, let slug) = result {
            XCTAssertEqual(dir, URL(fileURLWithPath: "/tmp/skills/foo")); XCTAssertEqual(slug, "foo")
        } else { XCTFail("expected .success, got \(result)") }
    }

    func testParsesFailureStatusLine() async throws {
        let claude = try writeFakeClaude(printingFinalLine: #"{"status":"error","message":"no narration detected"}"#)
        let result = try await SynthesisRunner.run(command: claude, arguments: [],
                                                   environment: nil, logFile: tmpDir.appendingPathComponent("synth.log"), timeoutSeconds: 30)
        if case .failure(let msg) = result { XCTAssertTrue(msg.contains("no narration detected")) }
        else { XCTFail("expected .failure, got \(result)") }
    }

    func testFailsWhenNoStatusLineFound() async throws {
        let claude = try writeFakeClaude(printingFinalLine: "no json here")
        let result = try await SynthesisRunner.run(command: claude, arguments: [],
                                                   environment: nil, logFile: tmpDir.appendingPathComponent("synth.log"), timeoutSeconds: 30)
        if case .failure = result { } else { XCTFail("expected .failure, got \(result)") }
    }

    func testFailsOnNonZeroExit() async throws {
        let claude = try writeFakeClaude(printingFinalLine: "anything", exitCode: 1)
        let result = try await SynthesisRunner.run(command: claude, arguments: [],
                                                   environment: nil, logFile: tmpDir.appendingPathComponent("synth.log"), timeoutSeconds: 30)
        if case .failure = result { } else { XCTFail("expected .failure, got \(result)") }
    }

    func testTimeoutSurfacesAsClearFailureMessage() async throws {
        let script = "#!/bin/bash\nsleep 5\n"
        let scriptURL = tmpDir.appendingPathComponent("slow-claude.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        let result = try await SynthesisRunner.run(command: scriptURL, arguments: [],
                                                   environment: nil, logFile: tmpDir.appendingPathComponent("synth.log"), timeoutSeconds: 1)
        if case .failure(let msg) = result { XCTAssertTrue(msg.lowercased().contains("timed out"), "got: \(msg)") }
        else { XCTFail("expected .failure on timeout, got \(result)") }
    }

    func testEnvironmentIsPassedToSubprocess() async throws {
        let script = """
        #!/bin/bash
        echo "{\\"status\\":\\"ok\\",\\"outputDir\\":\\"$SP_TEST_DIR\\",\\"slug\\":\\"x\\"}"
        """
        let scriptURL = tmpDir.appendingPathComponent("env-claude.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        var env = ProcessInfo.processInfo.environment
        env["SP_TEST_DIR"] = "/tmp/envcheck"
        let result = try await SynthesisRunner.run(command: scriptURL, arguments: [],
                                                   environment: env, logFile: tmpDir.appendingPathComponent("synth.log"), timeoutSeconds: 30)
        if case .success(let dir, _) = result { XCTAssertEqual(dir, URL(fileURLWithPath: "/tmp/envcheck")) }
        else { XCTFail("expected .success with env-derived dir, got \(result)") }
    }

    func testParseLastStatusLineDirectly() {
        let stdout = """
        intermediate line
        another line
        {"status":"ok","outputDir":"/tmp/x","slug":"x"}
        """.data(using: .utf8)!
        if case .success(let dir, let slug) = SynthesisRunner.parseLastStatusLine(stdout: stdout) {
            XCTAssertEqual(dir.path, "/tmp/x"); XCTAssertEqual(slug, "x")
        } else { XCTFail("expected .success") }
    }

    func testParseLastStatusLineHandlesTrailingTextAfterJSON() {
        let stdout = """
        intermediate
        {"status":"ok","outputDir":"/tmp/x","slug":"x"}
        cleanup output
        """.data(using: .utf8)!
        if case .success = SynthesisRunner.parseLastStatusLine(stdout: stdout) { } else { XCTFail("expected .success even with trailing text") }
    }
}
