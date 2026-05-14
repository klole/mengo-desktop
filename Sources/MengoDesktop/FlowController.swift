import Foundation
import Observation
import AppKit

/// Abstracts the synthesis subprocess so tests can stub it.
protocol SynthesisRunning: Sendable {
    func run(command: URL, arguments: [String], environment: [String: String]?,
             logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult
}

/// `SynthesisRunner.run` is an enum static; this thin struct conforms `SynthesisRunning`.
struct SystemSynthesisRunner: SynthesisRunning {
    func run(command: URL, arguments: [String], environment: [String: String]?,
             logFile: URL, timeoutSeconds: TimeInterval) async throws -> SynthesisResult {
        try await SynthesisRunner.run(command: command, arguments: arguments, environment: environment,
                                      logFile: logFile, timeoutSeconds: timeoutSeconds)
    }
}

/// Preflight health snapshot — abstracted so tests don't need a real recorder.
protocol FlowPreflightHealth: Sendable {
    func snapshot() async -> (healthy: Bool, audioPaused: Bool)
}

/// Reads the live `RecorderController` (Memory's recorder).
struct RecorderPreflightHealth: FlowPreflightHealth {
    weak var recorder: RecorderController?
    func snapshot() async -> (healthy: Bool, audioPaused: Bool) {
        await MainActor.run {
            guard let recorder else { return (healthy: false, audioPaused: false) }
            switch recorder.status {
            case .recording:                                  return (healthy: true, audioPaused: false)
            case .audioPaused, .bothPaused:                   return (healthy: true, audioPaused: true)
            case .screenPaused, .starting, .idle, .error:     return (healthy: false, audioPaused: false)
            }
        }
    }
}

/// Owns the Mengo Flow product: the record→synthesize→review→save loop. Adapted
/// from V1's `ScreenpipeFlow/{RecordingController,AppState}`. The recorder is
/// already running (owned by Mengo Memory / Phase 2), so Flow only preflights
/// it; it never starts the recorder.
@Observable
@MainActor
final class FlowController {

    enum PreflightFailure: Equatable {
        case recorderNotRunning
        case audioPaused
        case runtimeNotFound(SynthesisRuntime)
        case runtimeMCPNotConfigured(SynthesisRuntime)
    }

    /// Snapshot of the user's entitlement, captured at `save()` time.
    struct Entitlement { let isPro: Bool; let flowLimit: Int? }

    private(set) var flowState: FlowState = .idle
    private(set) var library: [FlowEntry] = []
    /// A quiet note shown in the Flow pane (e.g. "⌃⌥R is in use by another app").
    private(set) var hotkeyNote: String?

    // Injected deps.
    @ObservationIgnored private let recorderToken: String
    @ObservationIgnored private let executableOverride: (SynthesisRuntime) -> URL?
    @ObservationIgnored private let synthesisPrompt: String
    @ObservationIgnored let outputDir: URL          // ~/.claude/skills
    @ObservationIgnored private let manifestsDir: URL
    @ObservationIgnored private let recoveryDir: URL
    @ObservationIgnored private let libraryStore: FlowLibrary
    @ObservationIgnored private let synthesis: SynthesisRunning
    @ObservationIgnored private let health: FlowPreflightHealth
    @ObservationIgnored private let moments: MomentIndexing
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let entitlement: @MainActor () -> Entitlement
    @ObservationIgnored private let onFlowLimitReached: @MainActor () -> Void
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let hudShow: (FlowSession, @escaping () -> Void) -> Void
    @ObservationIgnored private let hudHide: () -> Void
    @ObservationIgnored private let notify: (String) -> Void
    @ObservationIgnored private let onPreflightFailure: @MainActor (PreflightFailure) -> Void

    /// The session captured between Start and Stop, kept after Stop so Regenerate
    /// can reuse it (and so a recovery dump on quit-mid-recording has the range).
    @ObservationIgnored private var lastSession: FlowSession?
    /// The manifest written for the last (re)synthesis, for Retry / source-id.
    @ObservationIgnored private var lastManifestURL: URL?

    init(recorderToken: String,
         executableOverride: @escaping (SynthesisRuntime) -> URL? = { $0.findExecutable() },
         synthesisPrompt: String,
         outputDir: URL,
         manifestsDir: URL,
         recoveryDir: URL,
         library: FlowLibrary,
         synthesis: SynthesisRunning = SystemSynthesisRunner(),
         health: FlowPreflightHealth,
         moments: MomentIndexing = NullMomentIndexing(),
         settings: SettingsStore,
         entitlement: @escaping @MainActor () -> Entitlement = { .init(isPro: true, flowLimit: nil) },
         onFlowLimitReached: @escaping @MainActor () -> Void = { FlowController.presentDefaultFlowLimitAlert() },
         now: @escaping () -> Date = Date.init,
         hudShow: @escaping (FlowSession, @escaping () -> Void) -> Void,
         hudHide: @escaping () -> Void,
         notify: @escaping (String) -> Void,
         onPreflightFailure: @escaping @MainActor (PreflightFailure) -> Void = { FlowController.presentDefaultPreflightAlert($0) }) {
        self.recorderToken = recorderToken
        self.executableOverride = executableOverride
        self.synthesisPrompt = synthesisPrompt
        self.outputDir = outputDir
        self.manifestsDir = manifestsDir
        self.recoveryDir = recoveryDir
        self.libraryStore = library
        self.synthesis = synthesis
        self.health = health
        self.moments = moments
        self.settings = settings
        self.entitlement = entitlement
        self.onFlowLimitReached = onFlowLimitReached
        self.now = now
        self.hudShow = hudShow
        self.hudHide = hudHide
        self.notify = notify
        self.onPreflightFailure = onPreflightFailure
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: manifestsDir, withIntermediateDirectories: true)
        self.library = libraryStore.load()
        AppDelegate.sharedFlowController = self
    }

    /// Production initializer wired to the live recorder + bundled prompt + discovered runtime executables.
    static func live(recorder: RecorderController,
                     hud: RecordingHUDController,
                     account: AccountStore,
                     settings: SettingsStore,
                     notify: @escaping (String) -> Void) -> FlowController {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MengoDesktop/flows", isDirectory: true)
        return FlowController(
            recorderToken: recorder.recorderToken,
            executableOverride: { $0.findExecutable() },
            synthesisPrompt: Self.loadSynthesisPrompt(),
            outputDir: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/skills", isDirectory: true),
            manifestsDir: appSupport.appendingPathComponent("manifests", isDirectory: true),
            recoveryDir: appSupport.appendingPathComponent("recovery", isDirectory: true),
            library: FlowLibrary(),
            health: RecorderPreflightHealth(recorder: recorder),
            moments: MemorySearchClient(token: recorder.recorderToken),
            settings: settings,
            entitlement: { [weak account] in .init(isPro: account?.isPro ?? false, flowLimit: account?.flowLimit) },
            hudShow: { session, onStop in hud.show(session: session, onStop: onStop) },
            hudHide: { hud.hide() },
            notify: notify)
    }

    static func loadSynthesisPrompt() -> String {
        if let url = Bundle.main.url(forResource: "synthesis-prompt", withExtension: "md"),
           let s = try? String(contentsOf: url, encoding: .utf8) { return s }
        Log.line("WARNING: synthesis-prompt.md not found in bundle — using minimal fallback")
        return """
        Synthesize a Claude Code skill from the recording described by the manifest at $MANIFEST_PATH. \
        Read the manifest, use the recorder MCP tools (mcp__screenpipe__*) to fetch the audio narration \
        (= intent), OCR/accessibility (= evidence), and key screenshots over the time range, then write \
        SKILL.md, flow.json, and frames/*.png into <outputDir>/<slug>/. On success print exactly: \
        {"status":"ok","outputDir":"<absolute path>","slug":"<slug>"}; on failure: {"status":"error","message":"<reason>"}.
        """
    }

    // MARK: - Preflight

    func preflight() async -> PreflightFailure? {
        let s = await health.snapshot()
        if !s.healthy { return .recorderNotRunning }
        if s.audioPaused { return .audioPaused }
        let runtime = settings.synthesisRuntime
        guard runtime.isAvailable, let exe = executableOverride(runtime) else { return .runtimeNotFound(runtime) }
        if await Self.mcpListLacksRecorderEntry(executable: exe, runtime: runtime) { return .runtimeMCPNotConfigured(runtime) }
        return nil
    }

    /// Best-effort: returns true only if `<exe> mcp list` *succeeds* and doesn't
    /// mention the recorder's MCP entry (literal substring "screenpipe", since that's
    /// the upstream MCP server's id). If we can't run it, don't block.
    private static func mcpListLacksRecorderEntry(executable: URL, runtime: SynthesisRuntime) async -> Bool {
        await Task.detached { () -> Bool in
            let p = Process(); p.executableURL = executable; p.arguments = runtime.mcpListArguments
            let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
            guard (try? p.run()) != nil else { return false }
            let data = out.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
            guard p.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return false }
            return runtime.mcpListLacksRecorderEntry(in: text)
        }.value
    }

    // MARK: - Recording lifecycle

    func toggleRecording() async {
        switch flowState {
        case .recording: await stop()
        case .browsingTimeline: cancelBrowsingTimeline()
        case .idle, .error: await start()
        default: break
        }
    }

    func start() async {
        switch flowState { case .idle, .error: break; default: return }
        if let failure = await preflight() { onPreflightFailure(failure); return }
        let session = FlowSession(mode: .proactive, bufferRangeStart: nil, activeRecordingStart: now(), endTime: nil)
        lastSession = session
        flowState = .recording(session)
        hudShow(session) { [weak self] in Task { @MainActor in await self?.stop() } }
    }

    // MARK: - Mode C: retroactive ("grab last N minutes")

    func beginBrowsingTimeline() { if case .idle = flowState { flowState = .browsingTimeline } }
    func cancelBrowsingTimeline() { if case .browsingTimeline = flowState { flowState = .idle } }

    /// Recent moments from the recorder's buffer for the picker (decimated to ≈one per 15 s).
    func loadMoments(lookbackMinutes: Int) async throws -> [Moment] {
        let end = now()
        return try await moments.momentIndex(from: end.addingTimeInterval(-Double(lookbackMinutes) * 60), to: end, limit: 400)
    }

    /// "Begin from here" in the picker. Preflight, then enter a `.retroactive`
    /// recording session — `bufferRangeStart` is the picked moment, `activeRecordingStart`
    /// is now. On a preflight failure, stay in `.browsingTimeline` (the picker stays open).
    func startRetroactive(bufferStart: Date) async {
        guard case .browsingTimeline = flowState else { return }
        if let failure = await preflight() { onPreflightFailure(failure); return }
        let session = FlowSession(mode: .retroactive, bufferRangeStart: bufferStart, activeRecordingStart: now(), endTime: nil)
        lastSession = session
        flowState = .recording(session)
        hudShow(session) { [weak self] in Task { @MainActor in await self?.stop() } }
    }

    func stop() async {
        guard case .recording(var session) = flowState else { return }
        hudHide()
        session.endTime = now()
        lastSession = session
        if session.durationSeconds < 10 {
            flowState = .idle
            notify("Recording too short to synthesize.")
            return
        }
        await runSynthesis(session: session, regen: nil)
    }

    // MARK: - Synthesis

    private func runSynthesis(session: FlowSession, regen: ManifestWriter.RegenerationContext?) async {
        let manifestURL: URL
        do {
            manifestURL = try ManifestWriter.write(
                session: session, outputDir: outputDir,
                userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
                regenerationContext: regen, manifestsDir: manifestsDir)
        } catch {
            flowState = .error("Couldn't write the recording manifest: \(error)")
            return
        }
        await synthesize(manifestURL: manifestURL)
    }

    /// Spawn the configured synthesis runtime against an already-written manifest, handle the result.
    private func synthesize(manifestURL: URL) async {
        lastManifestURL = manifestURL
        flowState = .synthesizing(manifestURL)

        let runtime = settings.synthesisRuntime
        guard runtime.isAvailable, let exe = executableOverride(runtime) else {
            flowState = .error("\(runtime.displayName) CLI not found.")
            return
        }
        let logURL = Log.synthesisLogURL(id: UUID().uuidString)
        let lastMessageFile = Log.directory.appendingPathComponent("synthesis-last-\(UUID().uuidString).txt")
        let prompt = synthesisPrompt.replacingOccurrences(of: "$MANIFEST_PATH", with: manifestURL.path)
        let invocation = runtime.invocation(executable: exe, skillsDir: outputDir, prompt: prompt, lastMessageFile: lastMessageFile)

        // ~/.claude/skills/ is behind the runtime's sensitive-file gate. Each runtime's
        // invocation builder embeds the right bypass flag + --add-dir whitelist.
        // SCREENPIPE_API_KEY: so the recorder MCP child (spawned by the runtime) can authenticate against Mengo's recorder.
        // PATH: a Finder-launched .app has a minimal PATH; prepend common locations so `claude`/`codex`/`npx`/`node` resolve.
        var env = ProcessInfo.processInfo.environment
        env["SCREENPIPE_API_KEY"] = recorderToken
        let home = NSHomeDirectory()
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:\(home)/.local/bin:\(home)/bin:" + (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")

        do {
            var result = try await synthesis.run(
                command: invocation.executable, arguments: invocation.arguments,
                environment: env, logFile: logURL, timeoutSeconds: 300)
            // Codex's `-o` file is belt-and-suspenders: if stdout had no JSON line, try the file.
            if case .file(let url) = invocation.finalStatusSource, case .failure = result,
               let data = try? Data(contentsOf: url) {
                result = SynthesisRunner.parseLastStatusLine(stdout: data)
            }
            switch result {
            case .success(let dir, let slug):
                let entry = FlowEntry(slug: slug, name: slug, path: dir, createdAt: now(),
                                      sourceManifestId: manifestURL.deletingPathExtension().lastPathComponent)
                libraryStore.add(entry); library = libraryStore.load()
                flowState = .reviewing(dir)
                notify("Skill ‘\(slug)’ ready for review.")
            case .failure(let message):
                flowState = .error("Synthesis failed: \(message)   (log: \(logURL.path))")
            }
        } catch {
            flowState = .error("Synthesis subprocess error: \(error)   (log: \(logURL.path))")
        }
    }

    // MARK: - Review actions

    func regenerate(feedback: String) async {
        guard case .reviewing(let prev) = flowState, let session = lastSession else { return }
        await runSynthesis(session: session, regen: .init(previousSkillPath: prev, userFeedback: feedback))
    }

    func retrySynthesis() async {
        guard case .error = flowState else { return }
        // Normal failures keep `lastSession`, so re-run from the session (rewrites the
        // manifest). A failed *recovery* synthesis has no session — re-run its manifest directly.
        if let session = lastSession { await runSynthesis(session: session, regen: nil) }
        else if let manifestURL = lastManifestURL { await synthesize(manifestURL: manifestURL) }
    }

    func discard() {
        if case .reviewing(let dir) = flowState {
            try? FileManager.default.removeItem(at: dir)
            libraryStore.remove(slug: dir.lastPathComponent); library = libraryStore.load()
        }
        if case .error = flowState, let m = lastManifestURL { try? FileManager.default.removeItem(at: m) }
        flowState = .idle
    }

    /// Apply Review edits and finalize. Renaming re-slugs the directory (collision → `-2` suffix);
    /// the new name is reflected in the library index. (The in-place SKILL.md rewrite of edited
    /// name/description/parameters is a follow-up — rename + library update is the critical path.)
    func save(name: String, description: String?, parameters: [FlowParameter]) {
        guard case .reviewing(let dir) = flowState else { return }
        // Gate Free users at the configured flow limit. The current `dir` is the unsaved
        // synthesis output — `libraryStore` already contains it from `runSynthesis`, plus
        // any earlier saved flows. The limit applies to the *kept* count (existing on disk).
        let ent = entitlement()
        if !ent.isPro, let limit = ent.flowLimit {
            let kept = libraryStore.load()
                .filter { $0.slug != dir.lastPathComponent && FileManager.default.fileExists(atPath: $0.path.path) }
                .count
            if kept >= limit { onFlowLimitReached(); return }
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = dir.deletingLastPathComponent()
        let siblings = Set((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? [])
        let desiredSlug = Slug.uniquify(Slug.derive(from: trimmed.isEmpty ? dir.lastPathComponent : trimmed),
                                        existing: siblings.subtracting([dir.lastPathComponent]))
        var finalDir = dir
        if desiredSlug != dir.lastPathComponent {
            let target = parent.appendingPathComponent(desiredSlug)
            if (try? FileManager.default.moveItem(at: dir, to: target)) != nil { finalDir = target }
        }
        libraryStore.remove(slug: dir.lastPathComponent)
        libraryStore.add(FlowEntry(slug: finalDir.lastPathComponent,
                                   name: trimmed.isEmpty ? finalDir.lastPathComponent : trimmed,
                                   path: finalDir, createdAt: now(),
                                   sourceManifestId: lastManifestURL?.deletingPathExtension().lastPathComponent))
        library = libraryStore.load()
        flowState = .idle
        notify("Saved to \(finalDir.path)")
    }

    // MARK: - Library actions

    func reopenInReview(slug: String) {
        if let e = library.first(where: { $0.slug == slug }) { flowState = .reviewing(e.path) }
    }
    func deleteFlow(slug: String) {
        if let e = library.first(where: { $0.slug == slug }) { try? FileManager.default.removeItem(at: e.path) }
        libraryStore.remove(slug: slug); library = libraryStore.load()
        if case .reviewing(let dir) = flowState, dir.lastPathComponent == slug { flowState = .idle }
    }

    // MARK: - Recovery

    func dumpRecoveryIfRecording() {
        guard case .recording(var session) = flowState else { return }
        session.endTime = now()
        try? FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        _ = try? ManifestWriter.write(session: session, outputDir: outputDir,
                                      userHintsName: nil, userHintsDescription: nil, userHintsNotes: nil,
                                      regenerationContext: nil, manifestsDir: recoveryDir)
    }

    /// The most recent recovery manifest, if any.
    func checkForRecovery() -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: recoveryDir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]),
              !entries.isEmpty else { return nil }
        return entries.filter { $0.pathExtension == "json" }.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }.first
    }

    /// Synthesize from an existing recovery manifest, then clear the recovery dir.
    func synthesizeRecovery(manifestURL: URL) async {
        await synthesize(manifestURL: manifestURL)
        try? FileManager.default.removeItem(at: recoveryDir)
    }

    // MARK: - Alerts

    static func presentDefaultPreflightAlert(_ f: PreflightFailure) {
        let a = NSAlert()
        switch f {
        case .recorderNotRunning:
            a.messageText = "The recorder isn't running"
            a.informativeText = "Mengo Flow needs Mengo Memory's recorder. Check the Memory tab."
        case .audioPaused:
            a.messageText = "Your microphone is paused"
            a.informativeText = "Flow needs the mic to capture your narration. Resume it from the Memory tab, then try again."
        case .runtimeNotFound(let runtime):
            a.messageText = "\(runtime.displayName) CLI not found"
            let where_ = runtime.executableSearchPaths.joined(separator: ", ")
            a.informativeText = "Install the \(runtime.displayName) CLI, then retry. Flow looked in: \(where_)"
        case .runtimeMCPNotConfigured(let runtime):
            a.messageText = "The Mengo MCP isn't set up for \(runtime.displayName)"
            a.informativeText = "Run this in a terminal, then retry:\n\n\(runtime.mcpAddCommand)"
            a.addButton(withTitle: "Copy command"); a.addButton(withTitle: "OK")
            if a.runModal() == .alertFirstButtonReturn {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(runtime.mcpAddCommand, forType: .string)
            }
            return
        }
        a.addButton(withTitle: "OK"); a.runModal()
    }

    /// Default action when a Free user tries to save past their flow limit.
    /// Opens the upgrade page via the global `AccountStore` (handoff URL).
    static func presentDefaultFlowLimitAlert() {
        let a = NSAlert()
        a.messageText = "You've used all your free flows"
        a.informativeText = "Upgrade to Mengo Pro for unlimited flows, or delete one from the Library to make room."
        a.addButton(withTitle: "Upgrade…")
        a.addButton(withTitle: "Cancel")
        if a.runModal() == .alertFirstButtonReturn {
            Task { @MainActor in
                let url = await AppDelegate.sharedAccount?.webURL(path: "/upgrade") ?? URL(string: "https://mengo.ai/upgrade")!
                NSWorkspace.shared.open(url)
            }
        }
    }
}
