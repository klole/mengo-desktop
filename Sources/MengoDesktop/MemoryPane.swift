import SwiftUI

/// The Memory product's pane — the on-device recorder, at a glance. Dark brand
/// palette; SF Symbol icons on every action; animated status + stats.
struct MemoryPane: View {
    let recorder: RecorderController
    @State private var appeared = false
    @State private var showSources = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let msg = degradedMessage { degradedBanner(msg) }
                controls
                Divider().overlay(Theme.separator)
                sessionSection
                Divider().overlay(Theme.separator)
                footer
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .background(
            LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground],
                           startPoint: .top, endPoint: .bottom)
        )
        .sheet(isPresented: $showSources) { RecordingSourcesView(recorder: recorder) }
        .animation(.spring(duration: 0.35), value: degradedMessage)
        .task {
            withAnimation(.easeOut(duration: 0.3)) { appeared = true }
            while !Task.isCancelled {
                await recorder.refreshRecordingsSize()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: - Hero

    @ViewBuilder private var hero: some View {
        HStack(alignment: .top, spacing: 12) {
            heroDot.padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text(heroTitle).font(Theme.title).foregroundStyle(heroColor)
                if let subtitle = heroSubtitle {
                    Text(subtitle).font(Theme.body).foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail = heroDetail {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.easeInOut(duration: 0.25), value: recorder.status)
    }

    @ViewBuilder private var heroDot: some View {
        switch recorder.status {
        case .recording:
            ZStack {
                Circle().fill(Theme.recording.opacity(0.20)).frame(width: 26, height: 26).blur(radius: 4)
                Image(systemName: "circle.fill").font(.system(size: 12))
                    .foregroundStyle(Theme.recording).symbolEffect(.pulse)
            }
        case .audioPaused, .screenPaused, .bothPaused:
            Image(systemName: "circle.fill").font(.system(size: 12)).foregroundStyle(Theme.paused)
        case .starting:
            ProgressView().controlSize(.small)
        case .idle:
            Image(systemName: "circle.dotted").font(.system(size: 12)).foregroundStyle(Theme.mutedText)
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

    private var degradedMessage: String? {
        guard recorder.status == .recording, let h = recorder.lastHealth else { return nil }
        if h.frameStatus != "ok" { return "Screen capture is degraded." }
        if h.audioStatus != "ok" { return "Microphone capture is degraded." }
        return nil
    }

    private func degradedBanner(_ msg: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.paused)
            Text(msg).font(Theme.body).foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Controls

    @ViewBuilder private var controls: some View {
        if case .error = recorder.status {
            Button { Task { await recorder.restartAfterCrash() } } label: {
                Label("Restart recorder", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
        } else {
            HStack(spacing: 10) {
                Button { Task { await bothAction() } } label: {
                    Label(bothTitle, systemImage: recorder.status == .bothPaused ? "play.circle.fill" : "pause.circle.fill")
                }
                .buttonStyle(.borderedProminent).tint(Theme.accent).disabled(disableControls)
                if recorder.runningAudioDisabled {
                    Label("Microphone off — no audio sources selected", systemImage: "mic.slash")
                        .font(Theme.caption).foregroundStyle(Theme.mutedText).labelStyle(.titleAndIcon)
                } else {
                    Button { Task { await audioAction() } } label: {
                        Label(audioTitle, systemImage: audioPausedNow ? "mic" : "mic.slash")
                    }
                    .buttonStyle(.bordered).disabled(disableControls)
                }
                Button { Task { await screenAction() } } label: {
                    Label(screenTitle, systemImage: screenPausedNow ? "rectangle" : "rectangle.slash")
                }
                .buttonStyle(.bordered).disabled(disableControls)
                Spacer(minLength: 12)
                Button { NSWorkspace.shared.open(recorder.dataFolderURL) } label: {
                    Label("Reveal recordings", systemImage: "folder")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button { showSources = true } label: {
                    Label("Configure sources…", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
            }
        }
    }

    private var disableControls: Bool {
        switch recorder.status { case .starting, .idle, .error: return true; default: return false }
    }
    private var audioPausedNow: Bool { switch recorder.status { case .audioPaused, .bothPaused: return true; default: return false } }
    private var screenPausedNow: Bool { switch recorder.status { case .screenPaused, .bothPaused: return true; default: return false } }
    private var bothTitle: String { recorder.status == .bothPaused ? "Resume both" : "Pause both" }
    private var audioTitle: String { audioPausedNow ? "Resume audio" : "Pause audio" }
    private var screenTitle: String { screenPausedNow ? "Resume screen" : "Pause screen" }
    private func bothAction() async { recorder.status == .bothPaused ? await recorder.resumeAll() : await recorder.pauseAll() }
    private func audioAction() async { audioPausedNow ? await recorder.resumeAudio() : await recorder.pauseAudio() }
    private func screenAction() async { screenPausedNow ? await recorder.resumeScreen() : await recorder.pauseScreen() }

    // MARK: - This session

    @ViewBuilder private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This session").font(Theme.headline).foregroundStyle(Theme.primaryText)
            HStack(spacing: 12) {
                StatTile(value: framesCaptured, label: "screens\ncaptured")
                StatTile(value: totalWords, label: "words\ntranscribed")
                StatTile(value: displayCount, label: "displays")
                StatTile(value: micCount, label: "mic\nsources")
            }
            HStack(spacing: 24) {
                if let last = lastCaptureText { metaLine("Last capture", last) }
                if let size = recorder.recordingsSizeBytes { metaLine("Recordings folder", MemoryFormatting.bytes(size)) }
            }
        }
        .opacity(recorder.status == .recording ? 1 : 0.55)
    }

    private func metaLine(_ label: String, _ value: String) -> some View {
        (Text(label + " · ").foregroundStyle(Theme.mutedText) + Text(value).foregroundStyle(Theme.secondaryText))
            .font(Theme.caption)
    }

    private var framesCaptured: Int? { recorder.lastHealth?.pipeline?.framesCaptured }
    private var totalWords: Int? { recorder.lastHealth?.audioPipeline?.totalWords }
    private var displayCount: Int? {
        recorder.runningMonitorIDs?.count ?? recorder.lastHealth?.monitors?.count
    }
    private var micCount: Int? {
        if recorder.runningAudioDisabled { return 0 }
        if let names = recorder.runningAudioDeviceNames { return names.count }
        return recorder.lastHealth?.audioPipeline?.audioDevices?.filter { $0.lowercased().contains("input") }.count
    }

    private var lastCaptureText: String? {
        guard let s = recorder.lastHealth?.lastFrameTimestamp, let d = MemoryFormatting.parseTimestamp(s) else { return nil }
        return MemoryFormatting.relative(from: d)
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Mengo Memory keeps a private, on-device record of what you see and hear. Nothing is uploaded.")
            .font(Theme.caption).foregroundStyle(Theme.mutedText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A "big number + small label" tile for the "This session" row. Rolls its
/// number with `.numericText`; lifts to `elevatedBackground` on hover.
private struct StatTile: View {
    let value: Int?
    let label: String
    @State private var hover = false

    var body: some View {
        VStack(spacing: 4) {
            Text(value.map(String.init) ?? "—")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .contentTransition(.numericText())
                .animation(.spring(duration: 0.4), value: value)
            Text(label).font(.system(size: 10)).foregroundStyle(Theme.mutedText)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(minWidth: 84)
        .padding(.vertical, 12).padding(.horizontal, 10)
        .background(hover ? Theme.elevatedBackground : Theme.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(hover ? Theme.accentGlow : Theme.separator))
        .onHover { hover = $0 }
        .animation(.easeInOut(duration: 0.15), value: hover)
    }
}
