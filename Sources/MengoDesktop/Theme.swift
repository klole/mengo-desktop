import SwiftUI
import AppKit

/// Mengo Desktop's design tokens, defined once. The colour/weight values
/// below are starter values — sampled from the app icon and the system
/// palette. If a fuller mengo.ai brand kit (typeface, extended palette)
/// becomes available, change it here.
enum Theme {

    // MARK: - Colours

    /// Brand accent — the warm orange of the app icon
    /// (≈ #FB8420; the icon's field runs ≈#FD9A1E → ≈#F96B1B top-to-bottom).
    static let accent = Color(red: 251.0 / 255.0, green: 132.0 / 255.0, blue: 32.0 / 255.0)

    /// Background behind the whole window / sidebar.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    /// Background behind a content pane.
    static let paneBackground = Color(nsColor: .textBackgroundColor)
    /// Hairline separators.
    static let separator = Color(nsColor: .separatorColor)
    /// Primary text.
    static let primaryText = Color(nsColor: .labelColor)
    /// De-emphasised / secondary text.
    static let secondaryText = Color(nsColor: .secondaryLabelColor)

    // MARK: - Status & surfaces

    /// Recorder is healthy and running.
    static let recording = Color.green
    /// Recorder is paused (audio, screen, or both).
    static let paused = Color(red: 0.92, green: 0.62, blue: 0.10)   // a calmer amber than .yellow
    /// Recorder stopped / errored.
    static let stopped = Color.red
    /// Subtle elevated fill for cards/tiles within a pane.
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    // MARK: - Typography

    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.semibold)
    static let title      = Font.system(.title, design: .default).weight(.semibold)
    static let headline   = Font.system(.headline, design: .default)
    static let body       = Font.system(.body, design: .default)
    static let caption    = Font.system(.caption, design: .default)
}
