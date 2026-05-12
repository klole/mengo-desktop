import Foundation

/// The five product/area sections in Mengo Desktop's main-window sidebar.
/// In Phase 1 each one shows a placeholder pane; later phases fill them in.
enum SidebarSection: String, CaseIterable, Identifiable {
    case memory
    case flow
    case library
    case studio
    case settings

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .memory:   return "Memory"
        case .flow:     return "Flow"
        case .library:  return "Library"
        case .studio:   return "Studio"
        case .settings: return "Settings"
        }
    }

    /// A short suffix shown after the name (sidebar row and menu item).
    /// `nil` for everything except Studio's "Pro" tag.
    var badge: String? {
        switch self {
        case .studio: return "Pro"
        default:      return nil
        }
    }

    /// SF Symbol name for the section's icon. (Indicative — fine to refine.)
    var systemImage: String {
        switch self {
        case .memory:   return "brain"
        case .flow:     return "wand.and.stars"
        case .library:  return "books.vertical"
        case .studio:   return "point.3.connected.trianglepath.dotted"
        case .settings: return "gearshape"
        }
    }

    /// The Mengo Desktop phase that replaces this section's placeholder with
    /// real content.
    var phase: Int {
        switch self {
        case .memory:   return 2
        case .flow:     return 3
        case .library:  return 3
        case .studio:   return 5
        case .settings: return 4
        }
    }

    /// One-line description shown on the placeholder pane.
    var comingSoonBlurb: String {
        switch self {
        case .memory:
            return "Always-on local recording of your screen, mic, and accessibility tree."
        case .flow:
            return "Record a task once and get a reusable Claude Code skill out of it."
        case .library:
            return "Your saved flows — re-open, rename, delete."
        case .studio:
            return "A visual editor for your flows, plus replay."
        case .settings:
            return "Capture, storage, hotkeys, account, privacy."
        }
    }
}
