import SwiftUI

/// The Memory Dashboard's hero region: page header + the orange-orb card.
///
/// Two horizontal regions:
///   1. **Page header** — `Memory` title + subtitle on the left; activity pill,
///      Start/Stop, and a settings gear on the right.
///   2. **Hero card** — the orange orb (always orange — it's the Mengo
///      mascot), the "Mengo is …" status word, three menu pills (Monitors /
///      Audio sources / Capture mode), and the primary Start/Stop +
///      Schedule Recording buttons.
struct MemoryHero: View {
    let recorder: RecorderController
    let settings: SettingsStore
    var onSchedule: () -> Void = {}
    var onShowAdvancedSources: () -> Void = {}
    var onShowSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            pageHeader
            heroCard
        }
    }

    // MARK: - Page header

    @ViewBuilder private var pageHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Memory").font(Theme.title).foregroundStyle(Theme.primaryText)
                Text("Your private, on-device memory layer. Always learning.")
                    .font(Theme.body).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 16)
            activityPill
            primaryButton
            settingsGear
        }
    }

    @ViewBuilder private var activityPill: some View {
        let label = activityPillLabel
        HStack(spacing: 8) {
            Circle().fill(label.color).frame(width: 8, height: 8)
            Text(label.text).font(Theme.body).foregroundStyle(Theme.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 22).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.separator, lineWidth: 1))
        )
    }

    @ViewBuilder private var primaryButton: some View {
        Button {
            Task { await togglePrimaryAction() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: primaryButtonIcon).font(.system(size: 13, weight: .semibold))
                Text(primaryButtonLabel).font(Theme.headline)
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(RoundedRectangle(cornerRadius: 22).fill(Theme.accent))
        }
        .buttonStyle(.plain)
        .disabled(recorder.status == .starting)
        .opacity(recorder.status == .starting ? 0.7 : 1)
    }

    @ViewBuilder private var settingsGear: some View {
        Button(action: onShowSettings) {
            Image(systemName: "gearshape").font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 36, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero card

    @ViewBuilder private var heroCard: some View {
        HStack(alignment: .top, spacing: 24) {
            MengoMemoryOrb(isRecording: orbIsRecording)
            VStack(alignment: .leading, spacing: 6) {
                Text(statusWord).font(Theme.largeTitle).foregroundStyle(Theme.primaryText)
                Text(statusSubtitle).font(Theme.body).foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                infoPillsRow.padding(.top, 18)
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Theme.cardBackground2)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.separator, lineWidth: 1))
        )
    }

    // MARK: - Info pills row

    @ViewBuilder private var infoPillsRow: some View {
        HStack(spacing: 12) {
            monitorsPill
            audioSourcesPill
            captureModePill
            scheduleButton
        }
    }

    @ViewBuilder private var monitorsPill: some View {
        Menu {
            let monitors = recorder.lastHealth?.monitors ?? []
            if monitors.isEmpty {
                Text("No monitors detected").foregroundStyle(.secondary)
            } else {
                ForEach(monitors, id: \.self) { name in
                    // For v1, list-only — actual per-monitor toggle still
                    // lives in the advanced sheet. Each row gets a checkmark
                    // to show it's recording.
                    Label(name, systemImage: "checkmark")
                }
            }
            Divider()
            Button("More options…", action: onShowAdvancedSources)
        } label: {
            pillContent(
                icon: "display",
                title: "Monitors",
                value: (recorder.lastHealth?.monitors ?? []).count.description + " " +
                       ((recorder.lastHealth?.monitors ?? []).count == 1 ? "Display" : "Displays"),
                detail: (recorder.lastHealth?.monitors ?? []).joined(separator: " · ")
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var audioSourcesPill: some View {
        Menu {
            let devices = recorder.lastHealth?.audioPipeline?.audioDevices ?? []
            if devices.isEmpty {
                Text("No audio sources").foregroundStyle(.secondary)
            } else {
                ForEach(devices, id: \.self) { name in
                    Label(name, systemImage: "checkmark")
                }
            }
            Divider()
            Button("More options…", action: onShowAdvancedSources)
        } label: {
            let devices = recorder.lastHealth?.audioPipeline?.audioDevices ?? []
            pillContent(
                icon: "waveform",
                title: "Audio sources",
                value: devices.first ?? "—",
                detail: devices.dropFirst().joined(separator: " · ")
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var captureModePill: some View {
        Menu {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                Button {
                    settings.captureMode = mode
                    // Restart the recorder if it's currently running so future
                    // supported capture-mode flags can take effect immediately.
                    if recorder.status.isRecording {
                        Task { await recorder.applyRecordingSources() }
                    }
                } label: {
                    if settings.captureMode == mode {
                        Label(mode.displayName, systemImage: "checkmark")
                    } else {
                        Text(mode.displayName)
                    }
                }
            }
        } label: {
            pillContent(
                icon: "camera",
                title: "Capture mode",
                value: settings.captureMode.displayName,
                detail: settings.captureMode.caption
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    @ViewBuilder private var scheduleButton: some View {
        Button(action: onSchedule) {
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 13))
                Text("Schedule Recording").font(Theme.body)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .foregroundStyle(Theme.primaryText)
            .background(
                RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    // Small horizontal info-pill, matching the mockup's three middle chips.
    private func pillContent(icon: String, title: String, value: String, detail: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.caption).foregroundStyle(Theme.mutedText)
                Text(value).font(Theme.body).foregroundStyle(Theme.primaryText)
                if !detail.isEmpty {
                    Text(detail).font(Theme.caption).foregroundStyle(Theme.secondaryText).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10).fill(Theme.cardBackground)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.separator, lineWidth: 1))
        )
    }

    // MARK: - State → strings

    private struct ActivityPillLabel { let text: String; let color: Color }

    private var activityPillLabel: ActivityPillLabel {
        switch recorder.status {
        case .idle:                                        return .init(text: "Memory Inactive",  color: Theme.stopped)
        case .starting:                                    return .init(text: "Starting…",        color: Theme.accent)
        case .recording:                                   return .init(text: "Memory Active",    color: Theme.recording)
        case .audioPaused, .screenPaused, .bothPaused:     return .init(text: "Memory Paused",    color: Theme.paused)
        case .error:                                       return .init(text: "Memory Error",     color: Theme.stopped)
        }
    }

    private var statusWord: String {
        switch recorder.status {
        case .idle:           return "Mengo is sleeping"
        case .starting:       return "Mengo is waking up…"
        case .recording:      return "Mengo is watching"
        case .audioPaused:    return "Mengo is watching"
        case .screenPaused:   return "Mengo is watching"
        case .bothPaused:     return "Mengo is paused"
        case .error:          return "Mengo hit a snag"
        }
    }

    private var statusSubtitle: String {
        switch recorder.status {
        case .idle:           return "Start watching to record and remember your world."
        case .starting:       return "Starting the on-device recorder…"
        case .recording:      return "Capturing your screen and microphone — everything stays on this Mac."
        case .audioPaused:    return "Still capturing your screen. Microphone capture is paused."
        case .screenPaused:   return "Still capturing your microphone. Screen capture is paused."
        case .bothPaused:     return "Screen and microphone capture are both paused."
        case .error(let m):   return m
        }
    }

    private var orbIsRecording: Bool {
        switch recorder.status {
        case .recording, .audioPaused, .screenPaused:
            return true
        case .idle, .starting, .bothPaused, .error:
            return false
        }
    }

    // MARK: - Primary button

    private var primaryButtonLabel: String {
        switch recorder.status {
        case .idle:                                  return "Start Watching"
        case .error:                                 return "Retry"
        case .starting:                              return "Starting…"
        case .recording:                             return "Stop Watching"
        case .audioPaused, .screenPaused, .bothPaused: return "Resume"
        }
    }

    private var primaryButtonIcon: String {
        switch recorder.status {
        case .recording: return "stop.fill"
        case .audioPaused, .screenPaused, .bothPaused: return "play.fill"
        case .error: return "arrow.clockwise"
        default: return "record.circle"
        }
    }

    private func togglePrimaryAction() async {
        switch recorder.status {
        case .idle:                                      await recorder.start()
        case .error:                                     await recorder.restartAfterCrash()
        case .recording:                                 recorder.stop()
        case .audioPaused, .screenPaused, .bothPaused:   await recorder.resumeAll()
        case .starting:                                  break
        }
    }
}

private struct MengoMemoryOrb: View {
    let isRecording: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breath = isRecording
                ? 1.0 + 0.035 * sin(t * 2.4)
                : 0.985 + 0.012 * sin(t * 0.9)
            let glow = isRecording
                ? 34 + 12 * (sin(t * 2.2) + 1) / 2
                : 15 + 4 * (sin(t * 0.8) + 1) / 2
            let shimmerX = 0.32 + 0.18 * sin(t * 1.1)
            let shimmerY = 0.30 + 0.08 * cos(t * 0.9)
            let rotation = Angle.degrees(isRecording ? t * 28 : t * 5)

            ZStack {
                if isRecording {
                    activeCorona(rotation: rotation, t: t)
                } else {
                    dormantHalo(rotation: rotation)
                }

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Theme.orbCore,
                                Theme.orbMid,
                                Theme.orbEdge
                            ],
                            center: .init(x: shimmerX, y: shimmerY),
                            startRadius: 5,
                            endRadius: 84
                        )
                    )
                    .overlay(surfaceSheen(t: t).clipShape(Circle()))
                    .overlay(innerShadow)
                    .overlay(rimStroke(rotation: rotation))
                    .shadow(color: Theme.orbGlow.opacity(isRecording ? 1.0 : 0.55), radius: glow)
                    .scaleEffect(breath)
            }
            .frame(width: 132, height: 132)
            .animation(.easeInOut(duration: 0.45), value: isRecording)
        }
    }

    private func activeCorona(rotation: Angle, t: TimeInterval) -> some View {
        ZStack {
            Circle()
                .stroke(
                    AngularGradient(
                        colors: [
                            .clear,
                            Theme.accent.opacity(0.10),
                            Theme.orbCore.opacity(0.72),
                            Theme.accent.opacity(0.18),
                            .clear,
                            Theme.orbCore.opacity(0.45),
                            .clear
                        ],
                        center: .center
                    ),
                    lineWidth: 5
                )
                .blur(radius: 0.7)
                .rotationEffect(rotation)
                .scaleEffect(1.08)

            Circle()
                .stroke(Theme.accent.opacity(0.12 + 0.08 * (sin(t * 2.0) + 1) / 2), lineWidth: 13)
                .blur(radius: 8)
                .scaleEffect(1.12)
        }
    }

    private func dormantHalo(rotation: Angle) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        Theme.orbMid.opacity(0.28),
                        Theme.orbCore.opacity(0.12),
                        Theme.orbEdge.opacity(0.0),
                        Theme.orbMid.opacity(0.22)
                    ],
                    center: .center
                ),
                lineWidth: 2
            )
            .rotationEffect(rotation)
            .scaleEffect(1.03)
            .blur(radius: 0.5)
    }

    private func surfaceSheen(t: TimeInterval) -> some View {
        let offset = isRecording ? 18 * sin(t * 1.25) : 6 * sin(t * 0.55)
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            .white.opacity(isRecording ? 0.23 : 0.14),
                            Theme.orbCore.opacity(isRecording ? 0.18 : 0.08),
                            .clear
                        ],
                        center: .init(x: 0.34, y: 0.28),
                        startRadius: 0,
                        endRadius: 48
                    )
                )
                .offset(x: offset, y: -offset * 0.35)

            LinearGradient(
                colors: [
                    .clear,
                    .white.opacity(isRecording ? 0.11 : 0.035),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .rotationEffect(.degrees(-18))
            .offset(x: isRecording ? 44 * sin(t * 1.15) : -24)
            .blendMode(.screen)
        }
    }

    private var innerShadow: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        .white.opacity(0.10),
                        .clear,
                        .black.opacity(0.34)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 2
            )
    }

    private func rimStroke(rotation: Angle) -> some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        Theme.orbEdge.opacity(0.25),
                        Theme.accent.opacity(isRecording ? 0.92 : 0.48),
                        Theme.orbCore.opacity(isRecording ? 0.65 : 0.28),
                        Theme.orbEdge.opacity(0.35)
                    ],
                    center: .center
                ),
                lineWidth: isRecording ? 1.6 : 1.1
            )
            .rotationEffect(rotation)
    }
}
