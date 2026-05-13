import SwiftUI

/// The main window: a logo-wordmark header over the section sidebar, with the
/// detail column showing the selected section's pane (real `MemoryPane` for
/// `.memory`, placeholders otherwise). Sidebar selection lives in `AppState`.
struct MainWindowView: View {
    let appState: AppState
    let recorder: RecorderController

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                wordmark
                List(selection: selectionBinding) {
                    ForEach(SidebarSection.allCases) { section in
                        Label {
                            HStack(spacing: 6) {
                                Text(section.displayName)
                                if let badge = section.badge {
                                    Spacer(minLength: 0)
                                    Text(badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(Theme.mutedText)
                                }
                            }
                        } icon: {
                            Image(systemName: section.systemImage)
                        }
                        .tag(section)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Theme.windowBackground)
            .frame(minWidth: 200)
            .tint(Theme.accent)
        } detail: {
            Group {
                switch appState.selectedSection {
                case .memory: MemoryPane(recorder: recorder)
                default:      ComingSoonPane(section: appState.selectedSection)
                }
            }
            .id(appState.selectedSection)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.22), value: appState.selectedSection)
        }
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

    private var selectionBinding: Binding<SidebarSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { if let newValue = $0 { appState.selectedSection = newValue } }
        )
    }
}
