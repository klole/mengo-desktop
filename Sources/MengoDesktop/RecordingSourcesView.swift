import SwiftUI

/// "Recording sources" sheet — pick which displays and microphones screenpipe
/// records. Styled after macOS → Settings → Displays: a row of display thumbnails
/// up top, an audio-device toggle list below, an "Apply & restart" footer.
/// Applying writes `RecordingSourcesStore` and restarts the recorder.
struct RecordingSourcesView: View {
    let recorder: RecorderController
    var store = RecordingSourcesStore()
    var catalog: RecordingSourceCatalog = ScreenpipeCLICatalog()
    @Environment(\.dismiss) private var dismiss

    @State private var loading = true
    @State private var loadError: String?
    @State private var monitors: [MonitorInfo] = []
    @State private var devices: [AudioDeviceInfo] = []
    @State private var selectedMonitorIDs: Set<Int> = []
    @State private var selectedDeviceNames: Set<String> = []
    // The selection that's actually running, captured on load — for the "changed?" check.
    @State private var baselineMonitorIDs: Set<Int> = []
    @State private var baselineDeviceNames: Set<String> = []
    @State private var applying = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if loading {
                Spacer()
                ProgressView("Looking for displays and microphones…").controlSize(.small)
                Spacer()
            } else if let loadError {
                Spacer(); errorView(loadError); Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        displayStrip
                        Divider().overlay(Theme.separator)
                        audioSection
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Divider().overlay(Theme.separator)
            footer
        }
        .frame(width: 540, height: 460)
        .background(Theme.windowBackground)
        .task { await load() }
    }

    private var header: some View {
        HStack {
            Text("Recording sources").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.paneBackground)
    }

    // MARK: Displays

    private var displayStrip: some View {
        VStack(alignment: .center, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 24) {
                    ForEach(monitors) { m in monitorThumb(m) }
                }
                .padding(.horizontal, 4).padding(.vertical, 6)
                .frame(maxWidth: .infinity)
            }
            Text(displayCaption).font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
        .frame(maxWidth: .infinity)
    }

    private func monitorThumb(_ m: MonitorInfo) -> some View {
        let on = selectedMonitorIDs.contains(m.id)
        let aspect = max(1.0, Double(m.width) / Double(max(1, m.height)))
        return VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(on ? Theme.accent : Theme.separator, lineWidth: on ? 2.5 : 1)
                    )
                    .frame(width: 116, height: 116 / aspect)
                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                        .background(Circle().fill(Theme.windowBackground).padding(2))
                        .offset(x: 6, y: -6)
                }
            }
            .frame(height: 78, alignment: .bottom)
            .opacity(on ? 1 : 0.4)
            .contentShape(Rectangle())
            .onTapGesture { toggleMonitor(m.id) }
            VStack(spacing: 1) {
                Text(m.name).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                Text("\(m.width)×\(m.height)").font(.system(size: 9)).foregroundStyle(Theme.mutedText)
                if m.isDefault {
                    Text("Main").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.mutedText)
                }
            }
            .frame(width: 128)
        }
    }

    private func toggleMonitor(_ id: Int) {
        if selectedMonitorIDs.contains(id) {
            guard selectedMonitorIDs.count > 1 else { return }   // always ≥1 display
            selectedMonitorIDs.remove(id)
        } else {
            selectedMonitorIDs.insert(id)
        }
    }

    private var displayCaption: String {
        let n = monitors.count
        return "Recording \(selectedMonitorIDs.count) of \(n) display\(n == 1 ? "" : "s")"
    }

    // MARK: Audio

    private var audioSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio sources").font(Theme.headline).foregroundStyle(Theme.primaryText)
            VStack(spacing: 0) {
                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, d in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.displayName).foregroundStyle(Theme.primaryText)
                            Text(kindLabel(d.kind)).font(Theme.caption).foregroundStyle(Theme.mutedText)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { selectedDeviceNames.contains(d.name) },
                            set: { on in
                                if on { selectedDeviceNames.insert(d.name) } else { selectedDeviceNames.remove(d.name) }
                            }
                        ))
                        .labelsHidden().tint(Theme.accent)
                    }
                    .padding(.vertical, 8).padding(.horizontal, 12)
                    if idx < devices.count - 1 { Divider().overlay(Theme.separator) }
                }
                if devices.isEmpty {
                    Text("No audio devices found.").font(Theme.caption).foregroundStyle(Theme.mutedText)
                        .padding(.vertical, 10).padding(.horizontal, 12)
                }
            }
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator))
            if !devices.isEmpty && selectedDeviceNames.isEmpty {
                Text("No audio sources — microphone capture will be off.")
                    .font(Theme.caption).foregroundStyle(Theme.paused)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kindLabel(_ k: AudioDeviceInfo.Kind) -> String {
        switch k {
        case .input: return "input"
        case .output: return "output"
        case .unknown: return "audio"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text("Changes restart recording.").font(Theme.caption).foregroundStyle(Theme.mutedText)
            Spacer()
            Button("Cancel") { dismiss() }
            Button {
                Task { await apply() }
            } label: {
                if applying { ProgressView().controlSize(.small) } else { Text("Apply & restart recording") }
            }
            .buttonStyle(.borderedProminent).tint(Theme.accent)
            .disabled(!canApply || applying)
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.paneBackground)
    }

    private var canApply: Bool {
        !loading && loadError == nil && !selectedMonitorIDs.isEmpty
            && (selectedMonitorIDs != baselineMonitorIDs || selectedDeviceNames != baselineDeviceNames)
    }

    // MARK: Load / apply

    private var defaultAudioSet: Set<String> {
        Set(devices.filter { $0.kind == .output || ($0.kind == .input && $0.isDefault) }.map(\.name))
    }

    private func load() async {
        do {
            async let m = catalog.availableMonitors()
            async let d = catalog.availableAudioDevices()
            let (mons, devs) = try await (m, d)
            monitors = mons
            devices = devs

            // Seed display selection from what's actually running, else "all".
            if let ids = recorder.runningMonitorIDs {
                selectedMonitorIDs = Set(ids)
            } else if let runningNames = recorder.lastHealth?.monitors, !runningNames.isEmpty {
                // /health gives names like "Display 1 (1728x1117)" — match by leading name.
                selectedMonitorIDs = Set(mons.filter { mon in runningNames.contains { $0.hasPrefix(mon.name) } }.map(\.id))
            }
            if selectedMonitorIDs.isEmpty { selectedMonitorIDs = Set(mons.map(\.id)) }

            // Seed audio selection.
            if let names = recorder.runningAudioDeviceNames {
                selectedDeviceNames = Set(names)
            } else if recorder.runningAudioDisabled {
                selectedDeviceNames = []
            } else if let live = recorder.lastHealth?.audioPipeline?.audioDevices, !live.isEmpty {
                selectedDeviceNames = Set(devs.filter { live.contains($0.name) }.map(\.name))
            } else {
                selectedDeviceNames = defaultAudioSet   // recorder down / unknown → screenpipe's default
            }

            baselineMonitorIDs = selectedMonitorIDs
            baselineDeviceNames = selectedDeviceNames
            loading = false
        } catch {
            loadError = "Couldn’t list displays/microphones (\(error.localizedDescription))."
            loading = false
        }
    }

    private func apply() async {
        applying = true
        // All displays selected ⇒ store nil (so a newly-plugged display is auto-included next launch).
        store.selectedMonitorIDs = (selectedMonitorIDs.count == monitors.count) ? nil : selectedMonitorIDs.sorted()
        // Audio: none ⇒ [] (disable); equals screenpipe's default set ⇒ nil; else the explicit names.
        if selectedDeviceNames.isEmpty { store.selectedAudioDeviceNames = [] }
        else if selectedDeviceNames == defaultAudioSet { store.selectedAudioDeviceNames = nil }
        else { store.selectedAudioDeviceNames = selectedDeviceNames.sorted() }
        await recorder.applyRecordingSources()
        applying = false
        dismiss()
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.paused)
            Text(msg).font(Theme.body).foregroundStyle(Theme.secondaryText).multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
