import SwiftUI

/// The main window: a logo-wordmark header over the section sidebar, with the
/// detail column showing the selected section's pane (real `MemoryPane` for
/// `.memory`, placeholders otherwise). Sidebar selection lives in `AppState`.
/// The sidebar rows are hand-drawn (rather than a `List(selection:)`) so the
/// selected-row highlight can be the brand orange — macOS sidebar lists otherwise
/// paint the selection in the system accent and ignore SwiftUI `.tint`.
struct MainWindowView: View {
    let appState: AppState
    let recorder: RecorderController
    let account: AccountStore
    let settings: SettingsStore
    let flow: FlowController
    let onSignOut: () -> Void

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                wordmark
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(SidebarSection.allCases.filter { $0 != .settings }) { section in
                            sidebarRow(section)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                }
                Spacer(minLength: 8)
                VStack(spacing: 8) {
                    if !account.isPro, !account.isLocalPreview {
                        Button {
                            Task { NSWorkspace.shared.open(await account.webURL(path: "/upgrade")) }
                        } label: {
                            Label("Purchase Mengo Pro", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                        Text("\(flow.library.filter(\.exists).count) of \(account.flowLimit ?? 3) free flows used")
                            .font(Theme.caption).foregroundStyle(Theme.mutedText)
                    }
                    sidebarRow(.settings)
                }
                .padding(.horizontal, 8).padding(.bottom, 10)
            }
            .background(Theme.windowBackground)
            .frame(minWidth: 200)
        } detail: {
            Group {
                switch appState.selectedSection {
                case .memory:   MemoryPane(recorder: recorder)
                case .flow:     FlowPane(flow: flow)
                case .library:  LibraryPane(flow: flow) { appState.selectedSection = .flow }
                case .settings: SettingsPane(account: account, settings: settings, recorder: recorder, flow: flow, onSignOut: onSignOut)
                default:        ComingSoonPane(section: appState.selectedSection)
                }
            }
            .id(appState.selectedSection)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: appState.selectedSection)
        }
    }

    private func sidebarRow(_ section: SidebarSection) -> some View {
        let selected = appState.selectedSection == section
        return Button {
            appState.selectedSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(selected ? Color.white : Theme.secondaryText)
                Text(section.displayName)
                    .foregroundStyle(selected ? Color.white : Theme.primaryText)
                Spacer(minLength: 0)
                if let badge = section.badge {
                    Text(badge).font(.caption2.weight(.semibold))
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.mutedText)
                }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Theme.accent : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private var wordmark: some View {
        HStack(spacing: 9) {
            if let logo = Brand.logo {
                logo.resizable().scaledToFit().frame(width: 22, height: 22)
            }
            Text("Mengo").font(.title3.weight(.bold)).foregroundStyle(Theme.primaryText)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)
    }
}
