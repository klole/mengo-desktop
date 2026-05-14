import SwiftUI
import AppKit

/// The Settings pane. Replaces the placeholder for `.settings` in `MainWindowView`.
/// Sections: Account / Synthesis model / Startup / Logs & data. Dark/orange palette
/// like the other panes; wrapped in a `ScrollView` so the window stays freely resizable.
struct SettingsPane: View {
    let account: AccountStore
    let settings: SettingsStore
    let recorder: RecorderController
    let flow: FlowController
    @State private var refreshing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                accountSection
                synthesisSection
                startupSection
                logsSection
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LinearGradient(colors: [Theme.paneBackground, Theme.windowBackground], startPoint: .top, endPoint: .bottom))
    }

    // MARK: Account

    @ViewBuilder private var accountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Account").font(Theme.headline).foregroundStyle(Theme.primaryText)
            if let a = account.account {
                HStack(spacing: 10) {
                    Text(a.email).font(Theme.body).foregroundStyle(Theme.secondaryText)
                    planBadge(a.plan)
                }
                if a.plan == .free {
                    let used = flow.library.filter(\.exists).count
                    let limit = account.flowLimit ?? 3
                    Text("\(used) of \(limit) flows used").font(Theme.caption).foregroundStyle(Theme.mutedText)
                    Button("Upgrade to Pro") {
                        Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) }
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                } else {
                    Button("Manage account") {
                        Task { NSWorkspace.shared.open(await account.webURL(path: "/account")) }
                    }
                    .buttonStyle(.bordered)
                }
                HStack(spacing: 10) {
                    Button("Refresh now") {
                        refreshing = true
                        Task { await account.refresh(); refreshing = false }
                    }
                    .buttonStyle(.bordered)
                    .disabled(refreshing)
                    if refreshing { ProgressView().controlSize(.small) }
                }
                Button("Sign out") { account.signOut() }
                    .buttonStyle(.plain).foregroundStyle(Theme.stopped)
            } else {
                Text("Not signed in.").font(Theme.body).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder private func planBadge(_ plan: Plan) -> some View {
        Text(plan == .pro ? "Pro" : "Free")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(
                Capsule().fill(plan == .pro ? Theme.accent : Theme.elevatedBackground)
            )
            .foregroundStyle(plan == .pro ? Color.white : Theme.secondaryText)
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
            Text("Mengo Flow uses this to turn recordings into reusable skills. Claude Code and Codex are configured automatically, and the Mengo MCP is wired into whichever you pick.")
                .font(Theme.caption).foregroundStyle(Theme.mutedText)
        }
    }

    @ViewBuilder private func runtimeRow(_ runtime: SynthesisRuntime) -> some View {
        let selected = settings.synthesisRuntime == runtime
        let disabled = !runtime.isAvailable
        Button {
            if !disabled { settings.synthesisRuntime = runtime }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? Theme.accent : Theme.mutedText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(runtime.displayName)
                        .font(Theme.body)
                        .foregroundStyle(disabled ? Theme.mutedText : Theme.primaryText)
                    if let note = runtime.comingSoonNote {
                        Text(note).font(Theme.caption).foregroundStyle(Theme.mutedText)
                    }
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
        .disabled(disabled)
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
