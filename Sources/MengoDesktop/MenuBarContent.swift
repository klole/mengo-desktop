import SwiftUI
import AppKit

/// The dropdown shown from the menu bar item. In Phase 1 the Memory and Flow
/// groups are present but disabled (those products don't exist yet);
/// Library / Studio / Settings raise the main window on that section; Quit
/// terminates.
struct MenuBarContent: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Mengo")
            .font(.headline)

        Divider()

        // MARK: Memory (Phase 2)
        Text("Memory")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("Pause audio") { }.disabled(true)
        Button("Pause screen") { }.disabled(true)
        Button("Open data folder") { }.disabled(true)

        // MARK: Flow (Phase 3)
        Text("Flow")
            .font(.caption)
            .foregroundStyle(.secondary)
        Button("Start recording…") { }.disabled(true)
        Button("Grab last 5 minutes…") { }.disabled(true)

        Divider()

        Button("Library") { reveal(.library) }
        Button(menuTitle(for: .studio)) { reveal(.studio) }
        Button("Settings…") { reveal(.settings) }

        Divider()

        Button("Quit Mengo Desktop") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    /// "Studio" + the section's badge in parens, e.g. "Studio (Pro)".
    private func menuTitle(for section: SidebarSection) -> String {
        if let badge = section.badge { return "\(section.displayName) (\(badge))" }
        return section.displayName
    }

    /// Select `section` in `AppState` and bring the main window to the front.
    private func reveal(_ section: SidebarSection) {
        appState.selectedSection = section
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
