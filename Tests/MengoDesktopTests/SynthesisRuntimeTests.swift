import XCTest
@testable import MengoDesktop

final class SynthesisRuntimeTests: XCTestCase {
    func test_availability_and_names() {
        XCTAssertTrue(SynthesisRuntime.ollama.isAvailable)
        XCTAssertTrue(SynthesisRuntime.claudeCode.isAvailable)
        XCTAssertTrue(SynthesisRuntime.codex.isAvailable)
        XCTAssertEqual(SynthesisRuntime.ollama.displayName, "Ollama (local — no account)")
        XCTAssertEqual(SynthesisRuntime.claudeCode.displayName, "Claude Code")
        XCTAssertEqual(SynthesisRuntime.allCases.count, 3)
    }
    func test_claudeCodeInvocation() {
        let exe = URL(fileURLWithPath: "/usr/local/bin/claude")
        let skills = URL(fileURLWithPath: "/Users/x/.claude/skills")
        let inv = SynthesisRuntime.claudeCode.invocation(executable: exe, skillsDir: skills, prompt: "PROMPT", lastMessageFile: URL(fileURLWithPath: "/tmp/x.txt"))
        XCTAssertEqual(inv.executable, exe)
        XCTAssertTrue(inv.arguments.contains("--safe-mode"))
        XCTAssertTrue(inv.arguments.contains("acceptEdits"))
        XCTAssertTrue(inv.arguments.contains(where: { $0.contains("screenpipe-mcp@0.18.10") }))
        XCTAssertFalse(inv.arguments.contains("--dangerously-skip-permissions"))
        XCTAssertEqual(inv.arguments.suffix(2), ["-p", "PROMPT"])
        if case .lastStdoutLine = inv.finalStatusSource {} else { XCTFail("expected lastStdoutLine") }
    }

    func test_claudeStudioInvocation_hasNoRecorderMCP() {
        let inv = SynthesisRuntime.claudeCode.invocation(
            executable: URL(fileURLWithPath: "/usr/local/bin/claude"),
            skillsDir: URL(fileURLWithPath: "/tmp/skill"), prompt: "PROMPT",
            lastMessageFile: URL(fileURLWithPath: "/tmp/x.txt"), recorderAccess: false)
        XCTAssertFalse(inv.arguments.contains("--mcp-config"))
        XCTAssertFalse(inv.arguments.contains(where: { $0.contains("screenpipe-mcp") }))
    }
    func test_codexInvocation() {
        let exe = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let skills = URL(fileURLWithPath: "/Users/x/.claude/skills")
        let last = URL(fileURLWithPath: "/tmp/last.txt")
        let inv = SynthesisRuntime.codex.invocation(executable: exe, skillsDir: skills, prompt: "PROMPT", lastMessageFile: last)
        XCTAssertTrue(inv.arguments.contains("workspace-write"))
        XCTAssertTrue(inv.arguments.contains("--ephemeral"))
        XCTAssertTrue(inv.arguments.contains(where: { $0.contains("screenpipe-mcp@0.18.10") }))
        XCTAssertFalse(inv.arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
        XCTAssertEqual(inv.arguments.suffix(3), ["--output-last-message", last.path, "PROMPT"])
        if case .file(let u) = inv.finalStatusSource { XCTAssertEqual(u, last) } else { XCTFail("expected .file") }
    }

    func test_ollamaInvocation_isLocalAndUsesSelectedModel() {
        let last = URL(fileURLWithPath: "/tmp/last.txt")
        let inv = SynthesisRuntime.ollama.invocation(
            executable: URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            skillsDir: URL(fileURLWithPath: "/tmp/skills"), prompt: "PROMPT",
            lastMessageFile: last, ollamaModel: "qwen3.5:27b")
        XCTAssertTrue(inv.arguments.contains("--oss"))
        XCTAssertTrue(inv.arguments.contains("ollama"))
        XCTAssertTrue(inv.arguments.contains("qwen3.5:27b"))
        XCTAssertTrue(inv.arguments.contains("workspace-write"))
        XCTAssertFalse(inv.arguments.contains("--dangerously-bypass-approvals-and-sandbox"))
    }
}
