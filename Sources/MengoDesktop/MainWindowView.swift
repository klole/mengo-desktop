import SwiftUI

/// The main window: a `NavigationSplitView` with a five-row sidebar and a
/// `ComingSoonPane` in the detail column. The sidebar selection lives in
/// `AppState` so the menu bar can drive it too.
struct MainWindowView: View {
    let appState: AppState

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
            ComingSoonPane(section: appState.selectedSection)
        }
    }

    /// `List` single-selection wants a `Binding<SidebarSection?>`; `AppState`
    /// keeps a non-optional `selectedSection`. Bridge here, ignoring any
    /// transient deselect-to-`nil`.
    private var selectionBinding: Binding<SidebarSection?> {
        Binding(
            get: { appState.selectedSection },
            set: { if let newValue = $0 { appState.selectedSection = newValue } }
        )
    }
}
