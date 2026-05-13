import SwiftUI
import AppKit

/// Brand assets bundled with the app.
enum Brand {
    /// The mengo.ai mango logo (transparent PNG). `nil` when running via
    /// `swift run` rather than the assembled `.app` — callers fall back to
    /// text-only branding.
    static let logo: Image? = {
        guard let url = Bundle.main.url(forResource: "MengoLogo", withExtension: "png"),
              let nsImage = NSImage(contentsOf: url)
        else { return nil }
        return Image(nsImage: nsImage)
    }()
}
