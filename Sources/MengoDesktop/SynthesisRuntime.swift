import Foundation

/// Which CLI Mengo Flow uses to turn a recording into a skill.
enum SynthesisRuntime: String, Codable, CaseIterable, Identifiable {
    case ollama, claudeCode, codex
    var id: String { rawValue }

    static let defaultOllamaModel = "gpt-oss:20b"
    static let screenpipeMCPVersion = "0.18.10"

    var displayName: String {
        switch self {
        case .ollama:     return "Ollama (local — no account)"
        case .claudeCode: return "Claude Code"
        case .codex:      return "Codex"
        }
    }
    var isAvailable: Bool { true }

    /// Where the final `{"status":...}` JSON line is read from after the subprocess exits.
    enum FinalStatusSource: Equatable { case lastStdoutLine; case file(URL) }
    struct Invocation { let executable: URL; let arguments: [String]; let finalStatusSource: FinalStatusSource }

    /// Builds a narrowly scoped non-interactive invocation. Recording synthesis
    /// gets only the pinned Screenpipe MCP; Studio-only edits get no MCP access.
    func invocation(executable: URL,
                    skillsDir: URL,
                    prompt: String,
                    lastMessageFile: URL,
                    ollamaModel: String = Self.defaultOllamaModel,
                    recorderAccess: Bool = true) -> Invocation {
        switch self {
        case .claudeCode:
            var args = ["--safe-mode", "--no-session-persistence",
                        "--permission-mode", "acceptEdits",
                        "--allowedTools", recorderAccess
                            ? "Read,Write,Edit,Glob,Grep,mcp__screenpipe__*"
                            : "Read,Write,Edit,Glob,Grep",
                        "--disallowedTools", "Bash,WebFetch,WebSearch"]
            if recorderAccess {
                args += ["--strict-mcp-config", "--mcp-config", Self.claudeMCPConfig]
            }
            args += ["--add-dir", skillsDir.path, "-p", prompt]
            return .init(executable: executable,
                         arguments: args,
                         finalStatusSource: .lastStdoutLine)
        case .codex, .ollama:
            var args = ["exec"]
            if self == .ollama {
                args += ["--oss", "--local-provider", "ollama", "--model", ollamaModel]
            }
            args += ["--sandbox", "workspace-write", "--ephemeral", "--ignore-user-config",
                     "--ignore-rules", "--skip-git-repo-check", "--add-dir", skillsDir.path]
            if recorderAccess {
                args += ["--config", "mcp_servers.screenpipe.command=\"npx\"",
                         "--config", "mcp_servers.screenpipe.args=[\"-y\",\"screenpipe-mcp@\(Self.screenpipeMCPVersion)\"]"]
            }
            args += ["--output-last-message", lastMessageFile.path, prompt]
            return .init(executable: executable,
                         arguments: args,
                         finalStatusSource: .file(lastMessageFile))
        }
    }

    var versionArguments: [String] { ["--version"] }

    private static let claudeMCPConfig = """
    {"mcpServers":{"screenpipe":{"type":"stdio","command":"npx","args":["-y","screenpipe-mcp@\(screenpipeMCPVersion)"]}}}
    """

    /// Where to look for this runtime's executable (mirrors `FlowController.findClaude()`).
    var executableSearchPaths: [String] {
        let home = NSHomeDirectory()
        switch self {
        case .codex, .ollama:
            return ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "\(home)/.local/bin/codex", "\(home)/bin/codex"]
        case .claudeCode:
            return ["/usr/local/bin/claude", "/opt/homebrew/bin/claude",
                    "\(home)/.claude/local/claude", "\(home)/.npm-global/bin/claude", "\(home)/.local/bin/claude"]
        }
    }
    func findExecutable() -> URL? {
        for p in executableSearchPaths where FileManager.default.isExecutableFile(atPath: p) { return URL(fileURLWithPath: p) }
        return nil
    }

    static var ollamaExecutableSearchPaths: [String] {
        let home = NSHomeDirectory()
        return ["/usr/local/bin/ollama", "/opt/homebrew/bin/ollama",
                "\(home)/.local/bin/ollama", "/Applications/Ollama.app/Contents/Resources/ollama"]
    }

    static func findOllamaExecutable() -> URL? {
        for path in ollamaExecutableSearchPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
