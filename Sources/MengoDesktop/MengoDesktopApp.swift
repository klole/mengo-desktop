import SwiftUI
import AppKit

@main
@MainActor
struct MengoDesktopApp: App {
    @State private var appState = AppState()
    @State private var recorder = RecorderController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Log.bootstrap()
    }

    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            MainWindowView(appState: appState, recorder: recorder)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 840, height: 560)

        MenuBarExtra {
            // MenuBarContent still has its Phase-1 init(appState:) here — Task 8
            // changes it to init(appState:recorder:) and the label below to MenuBarLabel.
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

/// Carries the lifecycle callbacks SwiftUI's scene phase doesn't reliably surface.
/// Starts the recorder on launch, stops it on quit. `sharedRecorder` is set by
/// `RecorderController.init()` (V1's bridge pattern).
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedRecorder: RecorderController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await AppDelegate.sharedRecorder?.start() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.sharedRecorder?.stop()
            Log.line("app terminating")
        }
    }
}
