import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    enum Status: Equatable {
        case idle
        case downloading(progress: Double)
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
        status = .downloading(progress: 0)
        do {
            let binaryURL = try await BinaryManager.ensureBinary { [weak self] p in
                Task { @MainActor in
                    self?.status = .downloading(progress: p)
                }
            }
            self.binaryVersion = (try? String(contentsOf: BinaryManager.versionFileURL, encoding: .utf8))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            await start(binaryURL: binaryURL)
        } catch {
            print("bootstrap error: \(error)")
            status = .error("Setup failed: \(error)")
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
        guard FileManager.default.isExecutableFile(atPath: BinaryManager.binaryURL.path) else {
            status = .error("Binary missing")
            return
        }
        visionPaused = false
        let wasAudioPaused = audioPaused
        await start(binaryURL: BinaryManager.binaryURL)
        if wasAudioPaused {
            try? await Task.sleep(for: .seconds(8))
            await pauseAudio()
        }
    }

    func restartAfterCrash() async {
        recorder.stop()
        healthTask?.cancel()
        await start(binaryURL: BinaryManager.binaryURL)
    }

    func retryDownload() async {
        try? FileManager.default.removeItem(at: BinaryManager.appSupportDir)
        await bootstrap()
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
