import Foundation

/// Which CLI Mengo Flow uses to turn a recording into a skill.
enum SynthesisRuntime: String, Codable, CaseIterable, Identifiable {
    case claudeCode, codex, cowork, customMCP
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        case .cowork:     return "Claude Cowork"
        case .customMCP:  return "Bring your own LLM (MCP)"
        }
    }
    var isAvailable: Bool { self == .claudeCode || self == .codex }
    var comingSoonNote: String? {
        switch self {
        case .cowork:    return "Coming soon."
        case .customMCP: return "Coming soon — point Mengo at your own model via an MCP server."
        default:         return nil
        }
    }

    /// Where the final `{"status":...}` JSON line is read from after the subprocess exits.
    enum FinalStatusSource: Equatable { case lastStdoutLine; case file(URL) }
    struct Invocation { let executable: URL; let arguments: [String]; let finalStatusSource: FinalStatusSource }

    /// Builds the spawn for this runtime. `lastMessageFile` is only used by `.codex` (`-o`).
    func invocation(executable: URL, skillsDir: URL, prompt: String, lastMessageFile: URL) -> Invocation {
        switch self {
        case .claudeCode:
            return .init(executable: executable,
                         arguments: ["--dangerously-skip-permissions", "--add-dir", skillsDir.path, "-p", prompt],
                         finalStatusSource: .lastStdoutLine)
        case .codex:
            return .init(executable: executable,
                         arguments: ["exec", "--dangerously-bypass-approvals-and-sandbox", "--skip-git-repo-check",
                                     "--add-dir", skillsDir.path, "-o", lastMessageFile.path, prompt],
                         finalStatusSource: .file(lastMessageFile))
        case .cowork, .customMCP:
            // Not reachable in practice (the picker disables these); fall back to Claude Code's shape.
            return SynthesisRuntime.claudeCode.invocation(executable: executable, skillsDir: skillsDir, prompt: prompt, lastMessageFile: lastMessageFile)
        }
    }

    var versionArguments: [String] { ["--version"] }
    var mcpListArguments: [String] { ["mcp", "list"] }
    func mcpListLacksScreenpipe(in output: String) -> Bool { !output.lowercased().contains("screenpipe") }
    var mcpAddCommand: String {
        switch self {
        case .codex: return "codex mcp add screenpipe -- npx -y screenpipe-mcp"
        default:     return "claude mcp add screenpipe -s user -- npx -y screenpipe-mcp"
        }
    }

    /// Where to look for this runtime's executable (mirrors `FlowController.findClaude()`).
    var executableSearchPaths: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .codex:
            return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/bin/codex"]
        default:
            return ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                    "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.local/bin/claude"]
        }
    }
    func findExecutable() -> URL? {
        for p in executableSearchPaths where FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }
}
