import SwiftUI
import AppKit

/// The dropdown shown from the menu bar item. In Phase 2 the "Memory" group is
/// live (pause/resume, open folder/log, restart-on-error); the "Flow" group is
/// still disabled (Phase 3); Library/Studio/Settings navigate the main window.
struct MenuBarContent: View {
    let appState: AppState
    let recorder: RecorderController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Mengo").font(.headline)
        Divider()

        // MARK: Memory
        Text("Memory").font(.caption).foregroundStyle(.secondary)
        bothItem
        audioItem
        screenItem
        if case .error = recorder.status {
            Button { Task { await recorder.restartAfterCrash() } } label: { Label("Restart recorder", systemImage: "arrow.clockwise") }
        }
        Button { NSWorkspace.shared.open(recorder.dataFolderURL) } label: { Label("Reveal recordings", systemImage: "folder") }
        Button { NSWorkspace.shared.open(recorder.recorderLogURL) } label: { Label("View log", systemImage: "doc.text") }

        // MARK: Flow (Phase 3)
        Text("Flow").font(.caption).foregroundStyle(.secondary)
        Button("Start recording…") { }.disabled(true)
        Button("Grab last 5 minutes…") { }.disabled(true)

        Divider()
        Button("Library") { reveal(.library) }
        Button(menuTitle(for: .studio)) { reveal(.studio) }
        Button("Settings…") { reveal(.settings) }

        Divider()
        Button("Quit Mengo Desktop") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder private var bothItem: some View {
        switch recorder.status {
        case .bothPaused:
            Button { Task { await recorder.resumeAll() } } label: { Label("Resume both", systemImage: "play.circle.fill") }
        case .recording, .audioPaused, .screenPaused:
            Button { Task { await recorder.pauseAll() } } label: { Label("Pause both", systemImage: "pause.circle.fill") }
        case .starting, .idle, .error:
            Button { } label: { Label("Pause both", systemImage: "pause.circle.fill") }.disabled(true)
        }
    }

    @ViewBuilder private var audioItem: some View {
        switch recorder.status {
        case .audioPaused, .bothPaused:
            Button { Task { await recorder.resumeAudio() } } label: { Label("Resume audio", systemImage: "mic") }
        default:
            Button { Task { await recorder.pauseAudio() } } label: { Label("Pause audio", systemImage: "mic.slash") }
                .disabled(!recorder.status.isRecording)
        }
    }

    @ViewBuilder private var screenItem: some View {
        switch recorder.status {
        case .screenPaused, .bothPaused:
            Button { Task { await recorder.resumeScreen() } } label: { Label("Resume screen", systemImage: "rectangle") }
        default:
            Button { Task { await recorder.pauseScreen() } } label: { Label("Pause screen", systemImage: "rectangle.slash") }
                .disabled(!recorder.status.isRecording)
        }
    }

    private func menuTitle(for section: SidebarSection) -> String {
        if let badge = section.badge { return "\(section.displayName) (\(badge))" }
        return section.displayName
    }

    private func reveal(_ section: SidebarSection) {
        appState.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The menu-bar item's label: "Mengo" plus a status-colored glyph.
struct MenuBarLabel: View {
    let status: RecorderStatus

    var body: some View {
        HStack(spacing: 4) {
            Text("Mengo")
            Image(systemName: glyph)
                .symbolRenderingMode(.palette)
                .foregroundStyle(color)
        }
    }

    private var glyph: String {
        switch status {
        case .recording: return "circle.fill"
        case .audioPaused, .screenPaused, .bothPaused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .starting, .idle: return "circle.dotted"
        }
    }
    private var color: Color {
        switch status {
        case .recording: return Theme.recording
        case .audioPaused, .screenPaused, .bothPaused: return Theme.paused
        case .error: return Theme.stopped
        case .starting, .idle: return .secondary
        }
    }
}
