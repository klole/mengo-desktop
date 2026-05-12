import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedState: AppState?
}

@main
struct ScreenpipeFlowApp: App {
    @State private var appState = AppState()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Logger.bootstrap()
    }

    var body: some Scene {
        MenuBarExtra("ScreenpipeFlow", systemImage: "waveform.circle") {
            Text("ScreenpipeFlow").font(.headline)
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
