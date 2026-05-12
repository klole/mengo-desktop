import Foundation
import Observation
import CoreGraphics
import AVFoundation
import ScreenCaptureKit

@Observable
@MainActor
final class AppState {
    enum Status: Equatable {
        case idle
        case starting
        case recording
        case audioPaused
        case visionPaused
        case bothPaused
        case error(String)

        var isRecording: Bool {
            switch self {
            case .recording, .audioPaused, .visionPaused, .bothPaused: return true
            default: return false
            }
        }
    }

    private(set) var status: Status = .idle
    private(set) var binaryVersion: String?

    @ObservationIgnored private let recorder: RecorderProcess
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private var healthTask: Task<Void, Never>?
    @ObservationIgnored private var audioPaused = false
    @ObservationIgnored private var visionPaused = false

    init() {
        let token = RecorderProcess.newToken()
        self.recorder = RecorderProcess(token: token)
        self.api = APIClient(token: token)
        AppDelegate.sharedState = self
        Task { await self.bootstrap() }
    }

    var logFileURL: URL { recorder.logFileURL }
    var dataFolderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".screenpipe")
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        do {
            let binaryURL = try BinaryManager.ensureBinary()
            self.binaryVersion = BinaryManager.bundledVersion()
            // Trigger permission dialogs for the .app FIRST, so macOS records the grants
            // against ScreenpipeMenu. The bundled helper at Contents/Helpers/screenpipe
            // then inherits the .app's TCC identity when spawned.
            await requestPermissionsIfNeeded()
            await start(binaryURL: binaryURL)
        } catch {
            status = .error("Bundled binary missing: \(error)")
        }
    }

    private func requestPermissionsIfNeeded() async {
        // Screen recording: SCShareableContent on macOS 14+ reliably triggers the prompt
        // and only resolves once the user has decided. CGRequestScreenCaptureAccess is
        // flaky on modern macOS (returns the cached state, doesn't always prompt).
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false,
                                                                     onScreenWindowsOnly: true)
        } catch {
            print("screen capture permission request failed: \(error)")
        }
        // Microphone.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            break
        }
    }

    private func start(binaryURL: URL) async {
        status = .starting
        audioPaused = false
        visionPaused = false
        do {
            try recorder.start(binaryURL: binaryURL)
        } catch {
            status = .error("Failed to start recorder: \(error)")
            return
        }
        startHealthPolling()
    }

    func quit() {
        healthTask?.cancel()
        recorder.stop()
        status = .idle
    }

    // MARK: - Pause / resume

    func pauseAudio() async {
        do {
            try await api.audioStop()
            audioPaused = true
            recomputeStatus()
        } catch {
            status = .error("Pause audio failed: \(error)")
        }
    }

    func resumeAudio() async {
        do {
            try await api.audioStart()
            audioPaused = false
            recomputeStatus()
        } catch {
            status = .error("Resume audio failed: \(error)")
        }
    }

    func pauseVision() {
        healthTask?.cancel()
        recorder.stop()
        visionPaused = true
        recomputeStatus()
    }

    func resumeVision() async {
        visionPaused = false
        let wasAudioPaused = audioPaused
        do {
            let binaryURL = try BinaryManager.ensureBinary()
            await start(binaryURL: binaryURL)
            if wasAudioPaused {
                try? await Task.sleep(for: .seconds(8))
                await pauseAudio()
            }
        } catch {
            status = .error("Resume failed: \(error)")
        }
    }

    func restartAfterCrash() async {
        recorder.stop()
        healthTask?.cancel()
        do {
            let binaryURL = try BinaryManager.ensureBinary()
            await start(binaryURL: binaryURL)
        } catch {
            status = .error("Restart failed: \(error)")
        }
    }

    // MARK: - Health polling

    private func startHealthPolling() {
        healthTask?.cancel()
        let api = self.api
        healthTask = Task { [weak self] in
            var failures = 0
            while !Task.isCancelled {
                do {
                    _ = try await api.health()
                    failures = 0
                    await MainActor.run {
                        guard let self else { return }
                        if case .starting = self.status {
                            self.recomputeStatus()
                        }
                    }
                } catch {
                    failures += 1
                    if failures >= 6 { // 30s of failures
                        await MainActor.run {
                            self?.status = .error("Recorder not responding")
                        }
                        return
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func recomputeStatus() {
        switch (audioPaused, visionPaused) {
        case (false, false): status = .recording
        case (true, false): status = .audioPaused
        case (false, true): status = .visionPaused
        case (true, true): status = .bothPaused
        }
    }
}
