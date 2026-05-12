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
            // .symbolRenderingMode(.palette) + .foregroundStyle on a colored Color is how
            // you get a non-template (i.e. actually colored) status bar item in macOS 13+.
            // Plain .foregroundColor gets template-stripped by NSStatusBarButton.
            HStack(spacing: 4) {
                Text(StatusBarLabel.text(for: appState.status))
                Image(systemName: StatusBarLabel.iconName(for: appState.status))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(StatusBarLabel.color(for: appState.status))
            }
            .foregroundStyle(StatusBarLabel.color(for: appState.status))
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Helpers for the menu bar label. Plain static functions — no custom View struct,
/// because SwiftUI's MenuBarExtra label slot is picky about what it'll render.
enum StatusBarLabel {
    static func text(for status: AppState.Status) -> String {
        switch status {
        case .idle: return "Idle"
        case .starting: return "Starting"
        case .recording: return "Recording"
        case .audioPaused: return "Audio paused"
        case .visionPaused: return "Screen paused"
        case .bothPaused: return "Paused"
        case .error: return "Error"
        }
    }

    static func color(for status: AppState.Status) -> Color {
        switch status {
        case .recording: return .green
        case .error: return .red
        case .audioPaused, .visionPaused, .bothPaused: return .yellow
        case .starting: return .blue
        case .idle: return .secondary
        }
    }

    static func iconName(for status: AppState.Status) -> String {
        switch status {
        case .idle: return "circle"
        case .starting: return "circle.dotted"
        case .recording: return "circle.fill"
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
