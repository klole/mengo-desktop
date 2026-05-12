import SwiftUI

@main
@MainActor
struct MengoDesktopApp: App {
    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            Text("Mengo Desktop")
                .frame(minWidth: 400, minHeight: 300)
        }
    }
}
