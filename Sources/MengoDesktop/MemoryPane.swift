import SwiftUI

/// The Memory product's pane — an at-a-glance view of the on-device recorder.
/// No "screenpipe" branding, no raw paths, no engine version: this is "Mengo Memory".
struct MemoryPane: View {
    let recorder: RecorderController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let msg = degradedMessage { degradedBanner(msg) }
                controls
                Divider()
                sessionSection
                Divider()
                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.paneBackground)
        .task {
            while !Task.isCancelled {
                await recorder.refreshRecordingsSize()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder private var hero: some View {
        HStack(alignment: .top, spacing: 11) {
            heroDot.padding(.top, 5)
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle).font(Theme.title).foregroundStyle(heroColor)
                if let subtitle = heroSubtitle {
                    Text(subtitle).font(Theme.body).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = heroDetail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var heroDot: some View {
        switch recorder.status {
        case .recording:
            Image(systemName: "circle.fill").font(.system(size: 12))
                .foregroundStyle(Theme.recording).symbolEffect(.pulse)
        case .audioPaused, .screenPaused, .bothPaused:
            Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(Theme.paused)
        case .starting:
            ProgressView().controlSize(.small)
        case .idle:
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 12)).foregroundStyle(Theme.stopped)
        }
    }

    private var heroColor: Color {
        switch recorder.status {
        case .recording: return Theme.recording
        case .audioPaused, .screenPaused, .bothPaused: return Theme.paused
        case .error: return Theme.stopped
        case .starting, .idle: return Theme.primaryText
        }
    }

    private var heroTitle: String {
        switch recorder.status {
        case .idle: return "Not recording"
        case .starting: return "Starting…"
        case .recording: return "Recording"
        case .audioPaused: return "Audio paused"
        case .screenPaused: return "Screen paused"
        case .bothPaused: return "Paused"
        case .error: return "Recorder stopped"
        }
    }

    private var heroSubtitle: String? {
        switch recorder.status {
        case .recording:    return "Capturing your screen and microphone — everything stays on this Mac."
        case .audioPaused:  return "Still capturing your screen. Microphone capture is paused."
        case .screenPaused: return "Still capturing your microphone. Screen capture is paused."
        case .bothPaused:   return "Screen and microphone capture are both paused."
        case .starting:     return "Starting the on-device recorder…"
        case .idle:         return nil
        case .error(let m): return m
        }
    }

    private var heroDetail: String? {
        guard let since = recorder.recordingSince else { return nil }
        let clock = since.formatted(date: .omitted, time: .shortened)
        let up = recorder.lastHealth?.pipeline?.uptimeSecs ?? 0
        return "Since \(clock) · \(MemoryFormatting.duration(seconds: up))"
    }

    // MARK: - Degraded banner

    /// Non-nil only when recording but `/health` reports a non-"ok" capture status.
    private var degradedMessage: String? {
        guard recorder.status == .recording, let h = recorder.lastHealth else { return nil }
        if h.frameStatus != "ok" { return "Screen capture is degraded — open the log for details." }
        if h.audioStatus != "ok" { return "Microphone capture is degraded — open the log for details." }
        return nil
    }

    private func degradedBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.paused)
            Text(msg).font(Theme.body).foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.paused.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if case .error = recorder.status {
            Button("Restart recorder") { Task { await recorder.restartAfterCrash() } }
                .buttonStyle(.borderedProminent)
        } else {
            HStack(spacing: 10) {
                Button(bothTitle) { Task { await bothAction() } }
                    .buttonStyle(.bordered)
                    .disabled(disableControls)
                Button(audioTitle) { Task { await audioAction() } }
                    .disabled(disableControls)
                Button(screenTitle) { Task { await screenAction() } }
                    .disabled(disableControls)
                Spacer(minLength: 12)
                Button("Reveal recordings") { NSWorkspace.shared.open(recorder.dataFolderURL) }
                    .buttonStyle(.link)
            }
        }
    }

    private var disableControls: Bool {
        switch recorder.status { case .starting, .idle, .error: return true; default: return false }
    }
    private var bothTitle: String { recorder.status == .bothPaused ? "Resume both" : "Pause both" }
    private var audioTitle: String {
        switch recorder.status { case .audioPaused, .bothPaused: return "Resume audio"; default: return "Pause audio" }
    }
    private var screenTitle: String {
        switch recorder.status { case .screenPaused, .bothPaused: return "Resume screen"; default: return "Pause screen" }
    }
    private func bothAction() async { recorder.status == .bothPaused ? await recorder.resumeAll() : await recorder.pauseAll() }
    private func audioAction() async {
        switch recorder.status { case .audioPaused, .bothPaused: await recorder.resumeAudio(); default: await recorder.pauseAudio() }
    }
    private func screenAction() async {
        switch recorder.status { case .screenPaused, .bothPaused: await recorder.resumeScreen(); default: await recorder.pauseScreen() }
    }

    // MARK: - This session

    @ViewBuilder private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This session").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack(spacing: 12) {
                StatTile(value: intOrDash(recorder.lastHealth?.pipeline?.framesCaptured), label: "screens\ncaptured")
                StatTile(value: intOrDash(recorder.lastHealth?.audioPipeline?.totalWords), label: "words\ntranscribed")
                StatTile(value: intOrDash(recorder.lastHealth?.monitors?.count), label: "displays")
                StatTile(value: intOrDash(micSourceCount), label: "mic\nsources")
            }
            HStack(spacing: 24) {
                if let last = lastCaptureText { metaLine("Last capture", last) }
                if let size = recorder.recordingsSizeBytes { metaLine("Recordings folder", MemoryFormatting.bytes(size)) }
            }
        }
        .opacity(recorder.status == .recording ? 1 : 0.55)
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        (Text(label + " · ").foregroundStyle(Theme.secondaryText) + Text(value).foregroundStyle(Theme.primaryText))
            .font(Theme.caption)
    }

    private var micSourceCount: Int? {
        recorder.lastHealth?.audioPipeline?.audioDevices?.filter { $0.lowercased().contains("input") }.count
    }

    private var lastCaptureText: String? {
        guard let s = recorder.lastHealth?.lastFrameTimestamp, let d = MemoryFormatting.parseTimestamp(s) else { return nil }
        return MemoryFormatting.relative(from: d)
    }

    private func intOrDash(_ n: Int?) -> String { n.map(String.init) ?? "—" }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Mengo Memory keeps a private, on-device record of what you see and hear. Nothing is uploaded.")
                .font(Theme.caption).foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("View log") { NSWorkspace.shared.open(recorder.recorderLogURL) }
                .buttonStyle(.link).font(Theme.caption)
        }
    }
}

/// A small "big number + small label" tile for the "This session" row.
private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.primaryText)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center).fixedSize()
        }
        .frame(minWidth: 84)
        .padding(.vertical, 12).padding(.horizontal, 10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}
