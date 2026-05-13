import SwiftUI

/// The main window: a `NavigationSplitView` with a five-row sidebar; the detail
/// column shows the section's pane (real `MemoryPane` for `.memory`, placeholders
/// for the rest in Phase 2). Sidebar selection lives in `AppState`.
struct MainWindowView: View {
    let appState: AppState
    let recorder: RecorderController

    var body: some View {
        NavigationSplitView {
            List(selection: selectionBinding) {
                ForEach(SidebarSection.allCases) { section in
                    Label {
                        HStack(spacing: 6) {
                            Text(section.displayName)
                            if let badge = section.badge {
                                Spacer(minLength: 0)
                                Text(badge)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                    } icon: {
                        Image(systemName: section.systemImage)
                    }
                    .tag(section)
                }
            }
            .navigationTitle("Mengo")
            .frame(minWidth: 190)
        } detail: {
            switch appState.selectedSection {
            case .memory: MemoryPane(recorder: recorder)
            default:      ComingSoonPane(section: appState.selectedSection)
            }
        }
    }

    private var selectionBinding: Binding<SidebarSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { if let newValue = $0 { appState.selectedSection = newValue } }
        )
    }
}
