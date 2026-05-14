import Foundation
import Observation
import AVFoundation
import ScreenCaptureKit

/// Owns the recorder lifecycle for Mengo Memory. Adapted from V1's
/// `ScreenpipeMenu/AppState.swift`, with dependencies injectable for tests.
@Observable
@MainActor
final class RecorderController {

    private(set) var status: RecorderStatus = .idle
    private(set) var recorderVersion: String?
    private(set) var lastHealth: RecorderHealth?
    private(set) var recordingsSizeBytes: Int64?

    /// What the live recorder process was actually started with — drives the
    /// "Recording sources" sheet's pre-selection / "changed?" check and the
    /// Memory pane's "displays" / "mic sources" tiles. `nil` ⇒ the recorder's
    /// default (all monitors / default mic + system audio).
    private(set) var runningMonitorIDs: [Int]?
    private(set) var runningAudioDeviceNames: [String]?
    private(set) var runningAudioDisabled = false

    /// The per-launch auth token the bundled recorder was started with — Flow
    /// passes it as `SCREENPIPE_API_KEY` to `claude -p` so the recorder MCP can
    /// query Mengo's recorder.
    let recorderToken: String

    @ObservationIgnored private let process: RecorderProcessControlling
    @ObservationIgnored private let api: RecorderHealthAPI
    @ObservationIgnored private let ensureBinaryClosure: () throws -> URL
    @ObservationIgnored private let requestPermissionsClosure: () async -> Void
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private let sourcesStore: RecordingSourcesStore
    @ObservationIgnored private let sourceCatalog: RecordingSourceCatalog
    @ObservationIgnored private(set) var healthTask: Task<Void, Never>?
    @ObservationIgnored private var audioPaused = false
    @ObservationIgnored private var screenPaused = false

    @ObservationIgnored private let captureModeProvider: @MainActor () -> CaptureMode
    @ObservationIgnored private let scheduleProvider: @MainActor () -> RecordingSchedule?

    init(
        processFactory: (String) -> RecorderProcessControlling = { RecorderProcess(token: $0) },
        apiFactory: (String) -> RecorderHealthAPI = { APIClient(token: $0) },
        ensureBinary: @escaping () throws -> URL = { try BinaryManager.ensureBinary() },
        requestPermissions: @escaping () async -> Void = RecorderController.requestSystemPermissions,
        pollInterval: Duration = .seconds(5),
        sourcesStore: RecordingSourcesStore = RecordingSourcesStore(),
        sourceCatalog: RecordingSourceCatalog = RecorderCLICatalog(),
        captureModeProvider: @escaping @MainActor () -> CaptureMode = { .smartCapture },
        scheduleProvider: @escaping @MainActor () -> RecordingSchedule? = { nil }
    ) {
        let token = RecorderProcess.newToken()
        self.recorderToken = token
        self.process = processFactory(token)
        self.api = apiFactory(token)
        self.ensureBinaryClosure = ensureBinary
        self.requestPermissionsClosure = requestPermissions
        self.pollInterval = pollInterval
        self.sourcesStore = sourcesStore
        self.sourceCatalog = sourceCatalog
        self.captureModeProvider = captureModeProvider
        self.scheduleProvider = scheduleProvider
        AppDelegate.sharedRecorder = self   // V1's bridge for the AppDelegate hooks
    }

    var dataFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screenpipe")
    }
    var recorderLogURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MengoDesktop/recorder.log")
    }

    /// When the current recording session started, derived from the recorder's reported uptime.
    var recordingSince: Date? {
        guard status == .recording, let up = lastHealth?.pipeline?.uptimeSecs else { return nil }
        return Date().addingTimeInterval(-up)
    }

    // MARK: - Lifecycle

    /// Called from `applicationDidFinishLaunching`. Ensures the bundled helper,
    /// requests TCC, spawns `screenpipe record`, begins health polling.
    func start() async {
        let binaryURL: URL
        do { binaryURL = try ensureBinaryClosure() }
        catch {
            status = .error("recorder helper missing — rebuild the app (\(error))")
            return
        }
        recorderVersion = BinaryManager.bundledVersion()
        await requestPermissionsClosure()
        await spawnAndPoll(binaryURL: binaryURL)
    }

    private func spawnAndPoll(binaryURL: URL) async {
        let sources = await buildSourceArguments()
        do { try process.start(binaryURL: binaryURL, extraArguments: sources.args) }
        catch {
            status = .error("failed to start recorder: \(error)")
            return
        }
        applyRunningState(sources)
        status = .starting
        startHealthPolling()
    }

    /// Called from `applicationWillTerminate` — synchronous on the main actor so it
    /// finishes before the OS reaps us.
    func stop() {
        healthTask?.cancel()
        healthTask = nil
        process.stop()
        status = .idle
    }

    // MARK: - Pause / resume

    func pauseAudio() async {
        do {
            try await api.audioStop()
            audioPaused = true
            recompute()
        } catch { status = .error("pause audio failed: \(error)") }
    }

    func resumeAudio() async {
        do {
            try await api.audioStart()
            audioPaused = false
            recompute()
        } catch { status = .error("resume audio failed: \(error)") }
    }

    func pauseScreen() async {
        healthTask?.cancel(); healthTask = nil
        process.stop()
        screenPaused = true
        recompute()
    }

    func resumeScreen() async {
        screenPaused = false
        let wasAudioPaused = audioPaused
        do {
            let binaryURL = try ensureBinaryClosure()
            let sources = await buildSourceArguments()
            try process.start(binaryURL: binaryURL, extraArguments: sources.args)
            applyRunningState(sources)
            status = .starting
            startHealthPolling()
            if wasAudioPaused {
                try? await Task.sleep(for: .seconds(8))
                await pauseAudio()
            }
        } catch { status = .error("resume screen failed: \(error)") }
    }

    func restartAfterCrash() async {
        process.stop()
        healthTask?.cancel(); healthTask = nil
        audioPaused = false; screenPaused = false
        do {
            let binaryURL = try ensureBinaryClosure()
            await spawnAndPoll(binaryURL: binaryURL)
        } catch { status = .error("restart failed: \(error)") }
    }

    /// Enforce the user's saved recording schedule. Called from the
    /// health-poll task each tick. No-op for `nil`. The state machine:
    ///   - active rule + currently `.bothPaused` → resume.
    ///   - no active rule + currently recording  → pause.
    /// Manual `.idle` / `.starting` / `.error` states are not touched —
    /// schedules don't auto-start a stopped recorder.
    func applySchedule(_ schedule: RecordingSchedule?, now: Date = Date()) async {
        guard let schedule, !schedule.rules.isEmpty else { return }
        let active = schedule.isActive(at: now)
        if active && status == .bothPaused {
            await resumeAll()
        } else if !active && status.isRecording {
            await pauseAll()
        }
    }

    /// The persisted source selection has changed (the caller already wrote
    /// `RecordingSourcesStore`). Restart the recorder so the new `--monitor-id` /
    /// `--audio-device` / `--disable-audio` flags take effect.
    func applyRecordingSources() async {
        process.stop()
        healthTask?.cancel(); healthTask = nil
        audioPaused = false; screenPaused = false
        do {
            let binaryURL = try ensureBinaryClosure()
            await spawnAndPoll(binaryURL: binaryURL)
        } catch { status = .error("applying recording sources failed: \(error)") }
    }

    // MARK: - Source arguments

    /// Translate the persisted source selection into `screenpipe record` flags.
    /// Monitor IDs are re-validated against the live display list; if none survive,
    /// fall back to "all monitors" (no flag). The (slow) display enumeration runs
    /// only when an explicit monitor selection exists.
    private func buildSourceArguments() async
        -> (args: [String], monitorIDs: [Int]?, audioNames: [String]?, audioDisabled: Bool) {
        var args: [String] = []
        var resolvedMonitorIDs: [Int]?

        if let wanted = sourcesStore.selectedMonitorIDs, !wanted.isEmpty {
            let liveIDs: [Int]? = (try? await sourceCatalog.availableMonitors()).map { $0.map { $0.id } }
            let surviving: [Int]
            if let liveIDs { surviving = wanted.filter { liveIDs.contains($0) } }
            else { surviving = wanted }   // catalog failed → trust the stored list
            if !surviving.isEmpty {
                resolvedMonitorIDs = surviving
                for id in surviving { args += ["--monitor-id", String(id)] }
            }
        }

        let audioNames = sourcesStore.selectedAudioDeviceNames
        var audioDisabled = false
        if let audioNames {
            if audioNames.isEmpty { args.append("--disable-audio"); audioDisabled = true }
            else { for name in audioNames { args += ["--audio-device", name] } }
        }

        // Capture-mode flags (--fps + variants). Comes from SettingsStore in
        // production; defaults to .smartCapture in tests that don't wire it.
        args += captureModeProvider().recorderFlags

        return (args, resolvedMonitorIDs, audioNames, audioDisabled)
    }

    private func applyRunningState(_ s: (args: [String], monitorIDs: [Int]?, audioNames: [String]?, audioDisabled: Bool)) {
        runningMonitorIDs = s.monitorIDs
        runningAudioDeviceNames = s.audioNames
        runningAudioDisabled = s.audioDisabled
    }

    func pauseAll() async {
        await pauseAudio()      // stop audio on the still-live process…
        await pauseScreen()     // …then kill the process
    }

    func resumeAll() async {
        audioPaused = false     // clear first so resumeScreen() doesn't re-pause audio
        await resumeScreen()
    }

    // MARK: - Recordings size

    /// Recompute the total size of `~/.screenpipe/` off the main actor. Cheap for typical
    /// folders; the Memory pane calls this when it appears and every ~60 s while visible.
    func refreshRecordingsSize() async {
        let dir = dataFolderURL
        let size = await Task.detached(priority: .utility) { () -> Int64? in
            guard let en = FileManager.default.enumerator(
                at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]) else { return nil }
            var total: Int64 = 0
            while let url = en.nextObject() as? URL {
                guard let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .isRegularFileKey]),
                      vals.isRegularFile == true else { continue }
                total += Int64(vals.totalFileAllocatedSize ?? 0)
            }
            return total
        }.value
        if let size { recordingsSizeBytes = size }
    }

    // MARK: - Health polling

    private func startHealthPolling() {
        healthTask?.cancel()
        let api = self.api
        let interval = self.pollInterval
        healthTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    let health = try await api.health()
                    failures = 0
                    await MainActor.run {
                        guard let self else { return }
                        self.lastHealth = health
                        if case .starting = self.status { self.recompute() }
                    }
                    // Enforce the user's recording schedule (if any) each tick.
                    if let self {
                        let schedule = await MainActor.run { self.scheduleProvider() }
                        await self.applySchedule(schedule)
                    }
                } catch {
                    failures += 1
                    if failures >= 6 {   // ~6 × pollInterval of consecutive failures
                        await MainActor.run { self?.status = .error("recorder not responding") }
                        return
                    }
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func recompute() {
        status = .from(audioPaused: audioPaused, screenPaused: screenPaused)
    }

    /// Test seam — force an `.error` without a real failure.
    func forceErrorForTesting(_ message: String) { status = .error(message) }

    // MARK: - TCC

    /// Trigger the Screen Recording + Microphone prompts so macOS records the grants
    /// against Mengo Desktop; the bundled helper then inherits them. V1's approach.
    /// `nonisolated` so it's a plain `() async -> Void` usable as the closure default.
    nonisolated static func requestSystemPermissions() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch { print("screen-capture permission request failed: \(error)") }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }
    }
}
