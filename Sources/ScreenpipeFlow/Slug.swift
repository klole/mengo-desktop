import Foundation

enum Slug {
    private static let maxLength = 60
    private static let fallback = "untitled-flow"

    static func derive(from input: String) -> String {
        let lower = input.lowercased()
        let scalars = lower.unicodeScalars.map { scalar -> Character in
            let c = Character(scalar)
            if c.isLetter || c.isNumber { return c }
            return "-"
        }
        var collapsed = String(scalars)
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }
        let trimmed = collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.isEmpty { return fallback }
        if trimmed.count <= maxLength { return trimmed }
        let prefix = trimmed.prefix(maxLength)
        return String(prefix).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    /// Returns a slug that does not collide with `existing` by appending -2, -3, …
    static func uniquify(_ slug: String, existing: Set<String>) -> String {
        if !existing.contains(slug) { return slug }
        var n = 2
        while existing.contains("\(slug)-\(n)") { n += 1 }
        return "\(slug)-\(n)"
    }
}
