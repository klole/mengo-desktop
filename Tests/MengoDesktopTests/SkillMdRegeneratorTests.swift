import XCTest
@testable import MengoDesktop

final class SkillMdRegeneratorTests: XCTestCase {

    actor StubSynthesis: SynthesisRunning {
        var result: SynthesisResult
        private(set) var calls: [(command: URL, arguments: [String])] = []
        init(result: SynthesisResult) { self.result = result }
        func run(command: URL, arguments: [String], environment: [String: String]?,
                 logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult {
            calls.append((command, arguments))
            return result
        }
    }

    private static let dummyExe = URL(fileURLWithPath: "/tmp/fake-claude")

    func test_regenerate_returnsSuccess_whenRunnerReports_ok() async throws {
        let stub = StubSynthesis(result: .success(outputDir: URL(fileURLWithPath: "/tmp/x"), slug: "x"))
        let regen = SkillMdRegenerator(
            runtime: { .claudeCode },
            executableOverride: { _ in Self.dummyExe },
            synthesis: stub,
            recorderToken: "token")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-x")
        let result = await regen.regenerate(skillDir: dir)
        if case .failure(let e) = result { XCTFail("expected success, got \(e)") }
    }

    func test_regenerate_failsWhenRunnerReportsFailure() async throws {
        let stub = StubSynthesis(result: .failure(message: "model crashed"))
        let regen = SkillMdRegenerator(
            runtime: { .claudeCode },
            executableOverride: { _ in Self.dummyExe },
            synthesis: stub,
            recorderToken: "token")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-y")
        let result = await regen.regenerate(skillDir: dir)
        if case .failure(let err) = result {
            XCTAssertTrue(err.errorDescription?.contains("model crashed") ?? false,
                          "errorDescription = \(err.errorDescription ?? "nil")")
        } else {
            XCTFail("expected .failure")
        }
    }

    func test_regenerate_failsWhenRuntimeExecutableNotFound() async throws {
        let stub = StubSynthesis(result: .success(outputDir: URL(fileURLWithPath: "/tmp/x"), slug: "x"))
        let regen = SkillMdRegenerator(
            runtime: { .claudeCode },
            executableOverride: { _ in nil },
            synthesis: stub,
            recorderToken: "token")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("skill-x")
        let result = await regen.regenerate(skillDir: dir)
        if case .failure(let err) = result {
            XCTAssertEqual(err, .runtimeNotFound(.claudeCode))
        } else {
            XCTFail("expected runtimeNotFound failure")
        }
    }

    func test_regenerate_invokesRuntimeWithSkillDirAndPromptSubstitutions() async throws {
        let stub = StubSynthesis(result: .success(outputDir: URL(fileURLWithPath: "/tmp/x"), slug: "x"))
        let regen = SkillMdRegenerator(
            runtime: { .claudeCode },
            executableOverride: { _ in Self.dummyExe },
            synthesis: stub,
            recorderToken: "token")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("my-skill")
        _ = await regen.regenerate(skillDir: dir)
        let calls = await stub.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.command, Self.dummyExe)
        let prompt = calls.first?.arguments.last ?? ""
        XCTAssertTrue(prompt.contains(dir.path), "prompt missing SKILL_DIR substitution: \(prompt)")
        XCTAssertTrue(prompt.contains("my-skill"), "prompt missing SLUG substitution: \(prompt)")
        XCTAssertFalse(prompt.contains("$SKILL_DIR"), "prompt still has placeholder: \(prompt)")
        XCTAssertFalse(prompt.contains("$SLUG"), "prompt still has placeholder: \(prompt)")
        // --add-dir flag is part of the Claude Code invocation contract.
        XCTAssertTrue(calls.first?.arguments.contains("--add-dir") ?? false)
    }
}
