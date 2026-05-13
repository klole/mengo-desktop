import SwiftUI
import AppKit

@main
@MainActor
struct MengoDesktopApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            MainWindowView(appState: appState)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 840, height: 560)

        MenuBarExtra {
            MenuBarContent(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Text("Mengo")
                Image(systemName: "circle.dotted")
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Carries the lifecycle callbacks SwiftUI's scene phase doesn't reliably
/// surface — in particular `applicationWillTerminate` (logout/shutdown/⌘Q).
/// In Phase 1 it just logs; Phase 2 hooks recorder shutdown in here.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by `RecorderController.init()` (V1's bridge). Task 7 wires the
    /// launch/terminate hooks that use it.
    @MainActor static weak var sharedRecorder: RecorderController?

    func applicationWillTerminate(_ notification: Notification) {
        Log.line("app terminating")
    }
}
