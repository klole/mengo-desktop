import Foundation

/// Regenerates `SKILL.md` for a saved skill from its current `flow.json` by
/// invoking the user's synthesis runtime (Claude Code / Codex). Studio uses
/// this after an edit so the skill's prose matches the structured changes —
/// without re-running a full recording-driven synthesis (no MCP / recorder
/// needed; the model just reads the local `flow.json`).
struct SkillMdRegenerator: Sendable {

    enum RegenerateError: LocalizedError, Equatable {
        case runtimeNotFound(SynthesisRuntime)
        case spawnFailed(String)
        case subprocessFailed(String)

        var errorDescription: String? {
            switch self {
            case .runtimeNotFound(let r): return "\(r.displayName) CLI not found."
            case .spawnFailed(let m):     return "Couldn't start the synthesis runtime: \(m)"
            case .subprocessFailed(let m): return m
            }
        }
    }

    /// Pulled lazily so a settings change is honored across regenerations.
    let runtime: @MainActor () -> SynthesisRuntime
    let ollamaModel: @MainActor () -> String
    let executableOverride: @Sendable (SynthesisRuntime) -> URL?
    let synthesis: SynthesisRunning
    /// Recorder MCP token — passed through for parity with the synthesis path,
    /// even though the regenerator doesn't query the recorder.
    let recorderToken: String

    init(runtime: @escaping @MainActor () -> SynthesisRuntime,
         ollamaModel: @escaping @MainActor () -> String = { SynthesisRuntime.defaultOllamaModel },
         executableOverride: @escaping @Sendable (SynthesisRuntime) -> URL?,
         synthesis: SynthesisRunning,
         recorderToken: String) {
        self.runtime = runtime
        self.ollamaModel = ollamaModel
        self.executableOverride = executableOverride
        self.synthesis = synthesis
        self.recorderToken = recorderToken
    }

    func regenerate(skillDir: URL) async -> Result<Void, RegenerateError> {
        let (runtime, ollamaModel) = await MainActor.run { (self.runtime(), self.ollamaModel()) }
        guard runtime.isAvailable, let exe = executableOverride(runtime) else {
            return .failure(.runtimeNotFound(runtime))
        }
        let slug = skillDir.lastPathComponent
        let prompt = Self.promptTemplate
            .replacingOccurrences(of: "$SKILL_DIR", with: skillDir.path)
            .replacingOccurrences(of: "$SLUG", with: slug)

        let lastMessageFile = Log.directory.appendingPathComponent("regen-last-\(UUID().uuidString).txt")
        // Whitelist only the target skill dir — the regenerator never needs
        // to read or write any other skill folder.
        let invocation = runtime.invocation(executable: exe,
                                            skillsDir: skillDir,
                                            prompt: prompt,
                                            lastMessageFile: lastMessageFile,
                                            ollamaModel: ollamaModel,
                                            recorderAccess: false)
        let logURL = Log.synthesisLogURL(id: "regen-\(UUID().uuidString)")

        var env = ProcessInfo.processInfo.environment
        env["SCREENPIPE_API_KEY"] = recorderToken
        let home = NSHomeDirectory()
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        do {
            var result = try await synthesis.run(
                command: invocation.executable, arguments: invocation.arguments,
                environment: env, logFile: logURL, timeoutSeconds: 180)
            if case .file(let url) = invocation.finalStatusSource, case .failure = result,
               let data = try? Data(contentsOf: url) {
                result = SynthesisRunner.parseLastStatusLine(stdout: data)
            }
            switch result {
            case .success: return .success(())
            case .failure(let message):
                return .failure(.subprocessFailed("Regenerate failed: \(message)   (log: \(logURL.path))"))
            }
        } catch {
            return .failure(.spawnFailed("\(error)"))
        }
    }

    /// Inline prompt — small enough that bundling a resource isn't worth it.
    /// The status-line contract matches the synthesis prompt so we can reuse
    /// `SynthesisRunner.parseLastStatusLine`.
    private static let promptTemplate = """
    You are regenerating the SKILL.md file for an existing Claude Code skill.

    SKILL_DIR: $SKILL_DIR
    SLUG: $SLUG

    Read $SKILL_DIR/flow.json. The user has edited the structured flow (steps,
    parameters, name, description). Rewrite $SKILL_DIR/SKILL.md so it reflects
    the current flow.json — keeping the existing frontmatter shape:

      ---
      name: <use flow.json "name" verbatim>
      description: <use flow.json "description" verbatim>
      ---

      <markdown body that describes the skill and walks through the steps>

    Rules:
    - Modify ONLY $SKILL_DIR/SKILL.md. Do NOT touch flow.json or any other file.
    - Keep references to frames/ images already in flow.json if they were there.
    - Use the user's edited "intent" text for each step; don't paraphrase steps.
    - Do not call any MCP tools — everything you need is in flow.json.

    On success print exactly: {"status":"ok","outputDir":"$SKILL_DIR","slug":"$SLUG"}
    On failure print exactly: {"status":"error","message":"<one-line reason>"}
    """
}
