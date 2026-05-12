import Foundation
import AppKit

@MainActor
final class RecordingController {
    enum PreflightFailure {
        case screenpipeNotRunning
        case audioPaused
        case claudeNotFound
        case tokenNotFound
    }

    private let state: AppState
    private let client: ScreenpipeClient
    private let manifestsDir: URL
    private let outputDir: URL
    private let synthesisPrompt: String
    private let claudeExecutable: URL?
    private let token: String?

    init(state: AppState) {
        self.state = state
        self.token = ScreenpipeTokenProvider.discover()
        self.client = ScreenpipeClient(token: token)

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("ScreenpipeFlow", isDirectory: true)
        self.manifestsDir = appSupport.appendingPathComponent("manifests", isDirectory: true)
        self.outputDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/skills", isDirectory: true)
        self.synthesisPrompt = Self.loadSynthesisPrompt()
        self.claudeExecutable = Self.findClaude()
        try? FileManager.default.createDirectory(at: manifestsDir,
                                                  withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: outputDir,
                                                  withIntermediateDirectories: true)
        Logger.log("RecordingController init: claude=\(claudeExecutable?.path ?? "nil") token=\(token != nil ? "yes" : "no")")
    }

    // Exposed for the Timeline window (so it can use the same authenticated client).
    func makeScreenpipeClient() -> ScreenpipeClient {
        ScreenpipeClient(token: token)
    }

    private static func loadSynthesisPrompt() -> String {
        if let url = Bundle.module.url(forResource: "synthesis-prompt", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) {
            return s
        }
        Logger.log("WARNING: synthesis-prompt.md not found in bundle")
        return "Synthesize a Claude Code skill from the manifest at $MANIFEST_PATH."
    }

    private static func findClaude() -> URL? {
        let home = NSHomeDirectory()
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.claude/local/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.local/bin/claude"
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    // MARK: - Preflight

    func preflight() async -> PreflightFailure? {
        do {
            let health = try await client.health()
            if !health.isHealthy { return .screenpipeNotRunning }
            if health.audioStatus == .paused { return .audioPaused }
        } catch {
            return .screenpipeNotRunning
        }
        if claudeExecutable == nil { return .claudeNotFound }
        if token == nil { return .tokenNotFound }
        return nil
    }

    // MARK: - Lifecycle

    func startProactive() async {
        if let failure = await preflight() {
            showPreflightDialog(failure)
            return
        }
        let session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
    }

    func startRetroactive(bufferStart: Date) async {
        if let failure = await preflight() {
            showPreflightDialog(failure)
            return
        }
        let session = RecordingSession(mode: .retroactive,
                                       bufferRangeStart: bufferStart,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
    }

    func stop() async {
        guard case .recording(var session) = state.sessionState else { return }
        session.endTime = Date()
        if session.durationSeconds < 10 {
            state.finalize()
            showAlert(title: "Recording too short",
                      message: "Synthesize a longer demonstration (>10 s).")
            return
        }
        state.lastSession = session
        await runSynthesis(for: session, regen: nil)
    }

    func regenerate(previousSkillPath: URL,
                    userFeedback: String,
                    originalSession: RecordingSession) async {
        let regen = ManifestWriter.RegenerationContext(
            previousSkillPath: previousSkillPath,
            userFeedback: userFeedback)
        await runSynthesis(for: originalSession, regen: regen)
    }

    // MARK: - Synthesis

    private func runSynthesis(for session: RecordingSession,
                              regen: ManifestWriter.RegenerationContext?) async {
        let manifestURL: URL
        do {
            manifestURL = try ManifestWriter.write(
                session: session,
                outputDir: outputDir,
                userHintsName: nil,
                userHintsDescription: nil,
                userHintsNotes: nil,
                regenerationContext: regen,
                manifestsDir: manifestsDir)
        } catch {
            state.setError("Failed to write manifest: \(error)")
            return
        }
        state.beginSynthesizing(manifest: manifestURL)

        guard let claude = claudeExecutable else {
            state.setError("Claude Code CLI not found")
            return
        }
        let logURL = Logger.synthesisLogURL(id: UUID().uuidString)
        let prompt = synthesisPrompt.replacingOccurrences(
            of: "$MANIFEST_PATH", with: manifestURL.path)

        do {
            // --add-dir whitelists ~/.claude/skills (which Claude Code treats as
            //   a sensitive-file path and would otherwise refuse to write to).
            // --permission-mode acceptEdits auto-accepts file edits so claude -p
            //   doesn't try to prompt for each write (which can't be answered
            //   in headless mode anyway).
            let result = try await SynthesisRunner.run(
                command: claude,
                arguments: [
                    "--add-dir", outputDir.path,
                    "--permission-mode", "acceptEdits",
                    "-p", prompt
                ],
                logFile: logURL,
                timeoutSeconds: 300)
            switch result {
            case .success(let dir, let slug):
                let entry = FlowEntry(slug: slug, name: slug,
                                      path: dir, createdAt: Date())
                state.addFlow(entry)
                state.lastSkillPath = dir
                state.beginReviewing(skill: dir)
                postCompletionNotification(slug: slug)
            case .failure(let message):
                state.setError("Synthesis failed: \(message). Log: \(logURL.path)")
            }
        } catch {
            state.setError("Synthesis subprocess error: \(error)")
        }
    }

    // MARK: - UI helpers

    private func showPreflightDialog(_ failure: PreflightFailure) {
        let alert = NSAlert()
        switch failure {
        case .screenpipeNotRunning:
            alert.messageText = "screenpipe is not running"
            alert.informativeText = "Open ScreenpipeMenu to start the recorder, then try again."
        case .audioPaused:
            alert.messageText = "Microphone capture is paused"
            alert.informativeText = "ScreenpipeFlow needs the microphone to capture your narration. Resume audio in ScreenpipeMenu and try again."
        case .claudeNotFound:
            alert.messageText = "Claude Code CLI not found"
            alert.informativeText = "Install from https://claude.ai/code, then retry. ScreenpipeFlow looked in /usr/local/bin, /opt/homebrew/bin, ~/.claude/local, ~/.npm-global/bin, and ~/.local/bin."
        case .tokenNotFound:
            alert.messageText = "screenpipe API key not found"
            alert.informativeText = "ScreenpipeFlow couldn't fetch a token via `screenpipe auth token`. Make sure ScreenpipeMenu has been launched at least once so the binary is on disk."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func postCompletionNotification(slug: String) {
        // For V1, just bring the app to the front. NSUserNotification is deprecated;
        // UserNotifications.framework is the modern path but requires entitlement
        // and permission grant. Keep it simple: just log + visual menu bar state.
        Logger.log("synthesis complete: \(slug)")
    }
}
