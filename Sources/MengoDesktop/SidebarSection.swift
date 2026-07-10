import Foundation

/// The five product areas in Mengo Desktop's main-window sidebar.
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
    var badge: String? { nil }

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

}
