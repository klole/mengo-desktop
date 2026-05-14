import SwiftUI
import AppKit

/// Mengo Desktop's design tokens — the mengo.ai brand dark palette (the app
/// forces `.darkAqua`, see `MengoDesktopApp`). Recorder-state colours are
/// functional, not part of the brand palette: green / brand-orange / red.
enum Theme {

    // MARK: - Brand palette (mengo.ai dark)

    static let windowBackground   = Color(hex: 0x121315)
    static let paneBackground     = Color(hex: 0x17181B)
    static let cardBackground     = Color(hex: 0x1D1F23)
    static let cardBackground2    = Color(hex: 0x202329)   // a notch lighter for dashboard cards
    static let elevatedBackground = Color(hex: 0x22242A)   // hover surface, one notch up
    static let separator          = Color(hex: 0x2A2D33)

    static let primaryText   = Color(hex: 0xF3F4F6)
    static let secondaryText = Color(hex: 0xA6ADB8)
    static let mutedText     = Color(hex: 0x737A86)

    static let accent      = Color(hex: 0xFF8A3D)
    static let accentHover = Color(hex: 0xFF9D5C)
    static let accentGlow  = Color(hex: 0xFF8A3D).opacity(0.18)

    // MARK: - Recorder state colours (functional)

    static let recording = Color(hex: 0x3DD56B)   // green — recording
    static let paused    = accent                  // orange — paused (audio/screen/both)
    static let stopped   = Color(hex: 0xE5484D)   // red — error

    // MARK: - Memory orb (the always-orange hero globe)
    // Always orange — it's the Mengo mascot. Status of the recorder is shown
    // separately in the activity pill at the top of the hero, never on the orb.
    static let orbCore   = Color(hex: 0xFFB06A)
    static let orbMid    = Color(hex: 0xD9740C)
    static let orbEdge   = Color(hex: 0x2A1206)
    static let orbGlow   = Color(hex: 0xFF8A3D).opacity(0.28)

    // MARK: - Typography

    static let largeTitle = Font.system(.largeTitle, design: .default).weight(.semibold)
    static let title      = Font.system(.title, design: .default).weight(.semibold)
    static let headline   = Font.system(.headline, design: .default)
    static let body       = Font.system(.body, design: .default)
    static let caption    = Font.system(.caption, design: .default)
}

private extension Color {
    /// Build an opaque sRGB colour from a 0xRRGGBB literal.
    init(hex: UInt) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255.0,
                  green: Double((hex >> 8)  & 0xFF) / 255.0,
                  blue:  Double( hex        & 0xFF) / 255.0,
                  opacity: 1.0)
    }
}
