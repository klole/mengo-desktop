import SwiftUI

/// The Memory product's pane in the main window. Reads the `RecorderController`.
struct MemoryPane: View {
    let recorder: RecorderController

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusHeader

            HStack(spacing: 24) {
                audioControl
                screenControl
            }

            if case .error(let message) = recorder.status {
                Button("Restart recorder") { Task { await recorder.restartAfterCrash() } }
                Text(message).font(Theme.caption).foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Recorder").font(Theme.headline)
                row("Data folder", recorder.dataFolderURL.path)
                row("Screen capture", recorder.lastHealth?.frameStatus ?? "—")
                row("Audio capture", recorder.lastHealth?.audioStatus ?? "—")
            }

            HStack {
                Button("Open data folder") { NSWorkspace.shared.open(recorder.dataFolderURL) }
                Button("Open recorder log") { NSWorkspace.shared.open(recorder.recorderLogURL) }
            }

            Spacer()
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paneBackground)
    }

    @ViewBuilder private var statusHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: glyph).foregroundStyle(color)
            Text(headline).font(Theme.title).foregroundStyle(color == .secondary ? Theme.primaryText : color)
        }
        if let v = recorder.screenpipeVersion {
            Text("screenpipe v\(v)").font(Theme.caption).foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder private var audioControl: some View {
        switch recorder.status {
        case .audioPaused, .bothPaused:
            Button("Resume audio") { Task { await recorder.resumeAudio() } }
        default:
            Button("Pause audio") { Task { await recorder.pauseAudio() } }
                .disabled(!recorder.status.isRecording)
        }
    }

    @ViewBuilder private var screenControl: some View {
        switch recorder.status {
        case .screenPaused, .bothPaused:
            Button("Resume screen") { Task { await recorder.resumeScreen() } }
        default:
            Button("Pause screen") { Task { await recorder.pauseScreen() } }
                .disabled(!recorder.status.isRecording)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 16)
            Text(value).foregroundStyle(Theme.primaryText)
        }
        .font(Theme.body)
        .frame(maxWidth: 420, alignment: .leading)
    }

    private var headline: String {
        switch recorder.status {
        case .idle:         return "Idle"
        case .starting:     return "Starting…"
        case .recording:    return "● Recording"
        case .audioPaused:  return "● Audio paused (screen recording)"
        case .screenPaused: return "● Screen paused (audio recording)"
        case .bothPaused:   return "● Paused"
        case .error(let m): return "⚠ \(m)"
        }
    }
    private var glyph: String {
        switch recorder.status {
        case .recording: return "circle.fill"
        case .audioPaused, .screenPaused, .bothPaused: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .starting, .idle: return "circle.dotted"
        }
    }
    private var color: Color {
        switch recorder.status {
        case .recording: return .green
        case .audioPaused, .screenPaused, .bothPaused: return .yellow
        case .error: return .red
        case .starting, .idle: return .secondary
        }
    }
}
