import SwiftUI

@main
struct ScreenpipeMenuApp: App {
    var body: some Scene {
        MenuBarExtra("Screenpipe", systemImage: "record.circle") {
            Text("ScreenpipeMenu — scaffolding")
            Divider()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.menu)
    }
}
