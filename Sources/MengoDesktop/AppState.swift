import Foundation
import Observation

/// App-wide state. In Phase 1 it holds just the sidebar selection — the
/// binding the main window's `List` and the menu bar's navigation entries
/// both drive. Later phases extend it (recorder status and Flow session).
@Observable
@MainActor
final class AppState {
    /// The section currently shown in the main window. Defaults to Memory,
    /// so the app opens on the Memory pane.
    var selectedSection: SidebarSection = .memory
}
