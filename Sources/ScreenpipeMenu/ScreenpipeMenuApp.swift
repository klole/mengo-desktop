import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedState: AppState?

    func applicationWillTerminate(_ notification: Notification) {
        // OS termination path (logout, shutdown, Cmd-Q). Stop the recorder synchronously
        // — we have a small window before the process is killed outright.
        MainActor.assumeIsolated {
            AppDelegate.sharedState?.quit()
        }
    }
}

@main
struct ScreenpipeMenuApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // When launched via Finder there's no attached terminal — redirect stdout/stderr
        // to a log file so users (and us) can see what the app is doing.
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Logs/ScreenpipeMenu", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        let appLog = logsDir.appendingPathComponent("app.log").path
        freopen(appLog, "a+", stdout)
        freopen(appLog, "a+", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        print("[\(Date())] app launched, pid=\(getpid())")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView(state: appState)
        } label: {
            Image(systemName: iconName(for: appState.status))
        }
        .menuBarExtraStyle(.menu)
    }

    private func iconName(for status: AppState.Status) -> String {
        switch status {
        case .idle: return "circle"
        case .starting: return "circle.dotted"
        case .recording: return "record.circle.fill"
        case .audioPaused, .visionPaused, .bothPaused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}

struct MenuView: View {
    let state: AppState

    var body: some View {
        Text(statusText)
            .font(.system(.body, design: .default).weight(.medium))

        if let v = state.binaryVersion {
            Text("screenpipe v\(v)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        Divider()

        if state.status.isRecording {
            switch state.status {
            case .audioPaused, .bothPaused:
                Button("Resume audio") { Task { await state.resumeAudio() } }
            default:
                Button("Pause audio") { Task { await state.pauseAudio() } }
            }
            switch state.status {
            case .visionPaused, .bothPaused:
                Button("Resume screen") { Task { await state.resumeVision() } }
            default:
                Button("Pause screen") { state.pauseVision() }
            }
            Divider()
        }

        if case .error = state.status {
            Button("Restart recorder") { Task { await state.restartAfterCrash() } }
            Divider()
        }

        Button("Open data folder") {
            NSWorkspace.shared.open(state.dataFolderURL)
        }
        Button("Open log file") {
            NSWorkspace.shared.open(state.logFileURL)
        }
        Button("Open Privacy Settings") {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
        Divider()
        Button("About ScreenpipeMenu") {
            let alert = NSAlert()
            alert.messageText = "ScreenpipeMenu"
            alert.informativeText = "Menu bar wrapper for screenpipe.\nhttps://github.com/screenpipe/screenpipe"
            alert.runModal()
        }
        Button("Quit") {
            state.quit()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var statusText: String {
        switch state.status {
        case .idle: return "Idle"
        case .starting: return "Starting…"
        case .recording: return "● Recording"
        case .audioPaused: return "● Audio paused (screen recording)"
        case .visionPaused: return "● Screen paused (audio recording)"
        case .bothPaused: return "● Paused"
        case .error(let msg): return "⚠ \(msg)"
        }
    }
}
