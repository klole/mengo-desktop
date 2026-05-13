import Foundation
import Observation
import AVFoundation
import ScreenCaptureKit

/// Owns the screenpipe recorder lifecycle for Mengo Memory. Adapted from V1's
/// `ScreenpipeMenu/AppState.swift`, with dependencies injectable for tests.
@Observable
@MainActor
final class RecorderController {

    private(set) var status: RecorderStatus = .idle
    private(set) var screenpipeVersion: String?
    private(set) var lastHealth: ScreenpipeHealth?

    @ObservationIgnored private let process: RecorderProcessControlling
    @ObservationIgnored private let api: RecorderHealthAPI
    @ObservationIgnored private let ensureBinaryClosure: () throws -> URL
    @ObservationIgnored private let requestPermissionsClosure: () async -> Void
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private(set) var healthTask: Task<Void, Never>?
    @ObservationIgnored private var audioPaused = false
    @ObservationIgnored private var screenPaused = false

    init(
        processFactory: (String) -> RecorderProcessControlling = { RecorderProcess(token: $0) },
        apiFactory: (String) -> RecorderHealthAPI = { APIClient(token: $0) },
        ensureBinary: @escaping () throws -> URL = { try BinaryManager.ensureBinary() },
        requestPermissions: @escaping () async -> Void = RecorderController.requestSystemPermissions,
        pollInterval: Duration = .seconds(5)
    ) {
        let token = RecorderProcess.newToken()
        self.process = processFactory(token)
        self.api = apiFactory(token)
        self.ensureBinaryClosure = ensureBinary
        self.requestPermissionsClosure = requestPermissions
        self.pollInterval = pollInterval
        AppDelegate.sharedRecorder = self   // V1's bridge for the AppDelegate hooks
    }

    var dataFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screenpipe")
    }
    var recorderLogURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/MengoDesktop/recorder.log")
    }

    // MARK: - Lifecycle

    /// Called from `applicationDidFinishLaunching`. Ensures the bundled helper,
    /// requests TCC, spawns `screenpipe record`, begins health polling.
    func start() async {
        let binaryURL: URL
        do { binaryURL = try ensureBinaryClosure() }
        catch {
            status = .error("screenpipe helper missing — rebuild the app (\(error))")
            return
        }
        screenpipeVersion = BinaryManager.bundledVersion()
        await requestPermissionsClosure()
        await spawnAndPoll(binaryURL: binaryURL)
    }

    private func spawnAndPoll(binaryURL: URL) async {
        do { try process.start(binaryURL: binaryURL) }
        catch {
            status = .error("failed to start recorder: \(error)")
            return
        }
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
            try process.start(binaryURL: binaryURL)
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
