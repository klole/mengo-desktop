import SwiftUI
import AppKit

/// Settings for synthesis, startup behavior, logs, and local app data.
struct SettingsPane: View {
    let settings: SettingsStore
    let recorder: RecorderController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                synthesisSection
                startupSection
                logsSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Synthesis model

    @ViewBuilder private var synthesisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Synthesis model").font(Theme.headline).foregroundStyle(Theme.primaryText)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(SynthesisRuntime.allCases) { runtime in
                    runtimeRow(runtime)
                }
            }
            if settings.synthesisRuntime == .ollama {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ollama model").font(Theme.caption).foregroundStyle(Theme.secondaryText)
                    TextField("gpt-oss:20b", text: Binding(
                        get: { settings.ollamaModel },
                        set: { settings.ollamaModel = $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    ))
                    .textFieldStyle(.roundedBorder)
                    Text("No account is required. Use a tool-capable model; Mengo recommends `gpt-oss:20b`. Install it with `ollama pull \(settings.ollamaModel)`.")
                        .font(Theme.caption).foregroundStyle(Theme.mutedText)
                }
            }
            Text("Mengo Flow uses the selected runtime to turn recordings into reusable skills. Ollama stays local; Claude Code and Codex use their respective cloud accounts.")
                .font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
    }

    @ViewBuilder private func runtimeRow(_ runtime: SynthesisRuntime) -> some View {
        let selected = settings.synthesisRuntime == runtime
        Button {
            settings.synthesisRuntime = runtime
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.mutedText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runtime.displayName)
                        .font(Theme.body)
                        .foregroundStyle(Theme.primaryText)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Theme.elevatedBackground : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: Startup

    @ViewBuilder private var startupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Startup").font(Theme.headline).foregroundStyle(Theme.primaryText)
            Toggle("Open Mengo Desktop at login",
                   isOn: Binding(get: { settings.openAtLogin },
                                 set: { settings.openAtLogin = $0 }))
                .toggleStyle(.switch).tint(Theme.accent)
            if let err = settings.loginItemError {
                Text(err).font(Theme.caption).foregroundStyle(Theme.stopped)
            }
            Toggle("Start recording when Mengo opens",
                   isOn: Binding(get: { settings.startRecordingOnLaunch },
                                 set: { settings.startRecordingOnLaunch = $0 }))
                .toggleStyle(.switch).tint(Theme.accent)
        }
    }

    // MARK: Logs & data

    @ViewBuilder private var logsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Logs & data").font(Theme.headline).foregroundStyle(Theme.primaryText)
            linkButton("Open recorder log", icon: "doc.text") {
                NSWorkspace.shared.open(recorder.recorderLogURL)
            }
            linkButton("Open Mengo log", icon: "doc.text") {
                NSWorkspace.shared.open(Log.fileURL)
            }
            linkButton("Reveal recordings folder", icon: "folder") {
                NSWorkspace.shared.open(recorder.dataFolderURL)
            }
            linkButton("Reveal Mengo data folder", icon: "folder") {
                let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("MengoDesktop", isDirectory: true)
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.open(url)
            }
        }
    }

    @ViewBuilder private func linkButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
            }
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
