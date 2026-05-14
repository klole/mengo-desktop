import Foundation

/// Pure aggregation + display-name/icon mapping for the Top Applications card
/// and the session-row icon stacks. No I/O.
enum AppUsageService {

    /// Build display-ready rows from raw frame counts. Percent is rounded to
    /// the nearest integer; the sum can drift by 1 from rounding.
    static func rows(from raw: [RawAppCount]) -> [AppUsageRow] {
        let total = raw.reduce(0) { $0 + $1.frameCount }
        guard total > 0 else { return [] }
        return raw.map { item in
            AppUsageRow(
                appName: item.appName,
                displayName: displayName(for: item.appName),
                iconName: iconName(for: item.appName),
                frameCount: item.frameCount,
                sharePercent: Int(round(Double(item.frameCount) / Double(total) * 100))
            )
        }
    }

    /// Map the recorder's raw `app_name` to a human-friendly label. Unknown
    /// apps pass through unchanged so we never silently lose information.
    static func displayName(for appName: String) -> String {
        knownAppDisplayNames[appName] ?? appName
    }

    /// SF Symbol name for the app icon. Unknown apps get a generic dashed
    /// square so the layout stays stable.
    static func iconName(for appName: String) -> String {
        knownAppIconNames[appName] ?? "square.dashed"
    }
}

// Curated mapping for the apps users actually run. Keep both display name AND
// icon keyed by the raw `app_name` macOS reports — there are usually a couple
// of variants (e.g. "Chrome" vs "Google Chrome") so we list both.
private let knownAppDisplayNames: [String: String] = [
    "Chrome":               "Google Chrome",
    "Google Chrome":        "Google Chrome",
    "Code":                 "VS Code",
    "Visual Studio Code":   "VS Code",
    "Slack":                "Slack",
    "Figma":                "Figma",
    "Notion":               "Notion",
    "Safari":               "Safari",
    "Terminal":             "Terminal",
    "iTerm2":               "Terminal",
    "Claude":               "Claude",
    "Xcode":                "Xcode",
    "Finder":               "Finder",
]

private let knownAppIconNames: [String: String] = [
    "Chrome":               "globe",
    "Google Chrome":        "globe",
    "Code":                 "chevron.left.forwardslash.chevron.right",
    "Visual Studio Code":   "chevron.left.forwardslash.chevron.right",
    "Slack":                "number",
    "Figma":                "rectangle.on.rectangle",
    "Notion":               "book.closed",
    "Safari":               "safari",
    "Terminal":             "terminal",
    "iTerm2":               "terminal",
    "Claude":               "sparkles",
    "Xcode":                "hammer",
    "Finder":               "folder",
]
