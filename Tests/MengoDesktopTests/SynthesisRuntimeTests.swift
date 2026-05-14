import XCTest
@testable import MengoDesktop

final class SynthesisRuntimeTests: XCTestCase {
    func test_availability_and_names() {
        XCTAssertTrue(SynthesisRuntime.claudeCode.isAvailable)
        XCTAssertTrue(SynthesisRuntime.codex.isAvailable)
        XCTAssertFalse(SynthesisRuntime.cowork.isAvailable)
        XCTAssertFalse(SynthesisRuntime.customMCP.isAvailable)
        XCTAssertEqual(SynthesisRuntime.claudeCode.displayName, "Claude Code")
        XCTAssertNotNil(SynthesisRuntime.cowork.comingSoonNote)
        XCTAssertNil(SynthesisRuntime.claudeCode.comingSoonNote)
        XCTAssertEqual(SynthesisRuntime.allCases.count, 4)
    }
    func test_claudeCodeInvocation() {
        let exe = URL(fileURLWithPath: "/usr/local/bin/claude")
        let skills = URL(fileURLWithPath: "/Users/x/.claude/skills")
        let inv = SynthesisRuntime.claudeCode.invocation(executable: exe, skillsDir: skills, prompt: "PROMPT", lastMessageFile: URL(fileURLWithPath: "/tmp/x.txt"))
        XCTAssertEqual(inv.executable, exe)
        XCTAssertEqual(inv.arguments, ["--dangerously-skip-permissions", "--add-dir", skills.path, "-p", "PROMPT"])
        if case .lastStdoutLine = inv.finalStatusSource {} else { XCTFail("expected lastStdoutLine") }
    }
    func test_codexInvocation() {
        let exe = URL(fileURLWithPath: "/opt/homebrew/bin/codex")
        let skills = URL(fileURLWithPath: "/Users/x/.claude/skills")
        let last = URL(fileURLWithPath: "/tmp/last.txt")
        let inv = SynthesisRuntime.codex.invocation(executable: exe, skillsDir: skills, prompt: "PROMPT", lastMessageFile: last)
        XCTAssertEqual(inv.arguments, ["exec", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check",
                                       "--add-dir", skills.path, "-o", last.path, "PROMPT"])
        if case .file(let u) = inv.finalStatusSource { XCTAssertEqual(u, last) } else { XCTFail("expected .file") }
    }
    func test_preflight_mcpListCheck() {
        XCTAssertTrue(SynthesisRuntime.claudeCode.mcpListLacksRecorderEntry(in: "no mcps here"))
        XCTAssertFalse(SynthesisRuntime.claudeCode.mcpListLacksRecorderEntry(in: "screenpipe   npx -y screenpipe-mcp"))
        XCTAssertEqual(SynthesisRuntime.codex.mcpAddCommand, "codex mcp add screenpipe -- npx -y screenpipe-mcp")
        XCTAssertEqual(SynthesisRuntime.claudeCode.mcpAddCommand, "claude mcp add screenpipe -s user -- npx -y screenpipe-mcp")
    }
}
