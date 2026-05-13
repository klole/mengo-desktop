import Foundation

/// One flow Mengo has created. `Identifiable` by `slug` for SwiftUI lists.
struct FlowEntry: Equatable, Identifiable, Codable {
    let slug: String
    var name: String
    let path: URL
    let createdAt: Date
    let sourceManifestId: String?
    var id: String { slug }

    /// True when the skill directory still exists on disk.
    var exists: Bool { FileManager.default.fileExists(atPath: path.path) }
}

/// JSON-backed index of the flows Mengo created, at
/// `~/Library/Application Support/MengoDesktop/flows/library.json` by default.
/// We don't scan `~/.claude/skills/` — only flows *we* made appear in the Library
/// pane; an externally-deleted one shows greyed via `FlowEntry.exists`.
struct FlowLibrary {
    let fileURL: URL

    init(fileURL: URL = FlowLibrary.defaultFileURL) { self.fileURL = fileURL }

    static var defaultFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MengoDesktop/flows", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    /// Newest first.
    func load() -> [FlowEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? Self.decoder.decode([FlowEntry].self, from: data)
        else { return [] }
        return entries.sorted { $0.createdAt > $1.createdAt }
    }

    func add(_ entry: FlowEntry) {
        var entries = load().filter { $0.slug != entry.slug }
        entries.append(entry)
        write(entries)
    }

    func remove(slug: String) { write(load().filter { $0.slug != slug }) }

    private func write(_ entries: [FlowEntry]) {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(entries) { try? data.write(to: fileURL, options: .atomic) }
    }

    private static let decoder: JSONDecoder = { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }()
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()
}
