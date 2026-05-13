import Foundation

/// A parameter declared in a synthesized skill's `flow.json`.
struct FlowParameter: Equatable, Identifiable {
    var name: String
    var description: String?
    var defaultValue: String?
    var autoDetected: Bool
    var id: String { name }
}

/// Pure parsers for a synthesized skill's files. Keeps `SkillReviewView` thin
/// and gives the fiddly bits (frontmatter, `flow.json`) a unit-tested home.
enum SkillFiles {

    /// Splits leading `---`-delimited YAML-ish frontmatter (`name:` / `description:`,
    /// where the description may continue onto indented lines) from the markdown body.
    static func parseSkillMarkdown(_ text: String) -> (name: String?, description: String?, body: String) {
        let lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closeIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return (nil, nil, text) }
        let fm = lines[1..<closeIdx]
        var name: String?
        var descParts: [String] = []
        var inDesc = false
        for raw in fm {
            if let r = raw.range(of: #"^\s*name\s*:\s*"#, options: .regularExpression) {
                name = String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces); inDesc = false
            } else if let r = raw.range(of: #"^\s*description\s*:\s*"#, options: .regularExpression) {
                descParts = [String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)]; inDesc = true
            } else if inDesc, raw.first == " " || raw.first == "\t" {
                descParts.append(raw.trimmingCharacters(in: .whitespaces))
            } else {
                inDesc = false
            }
        }
        let body = String(lines[(closeIdx + 1)...].joined(separator: "\n").drop(while: { $0 == "\n" }))
        let desc = descParts.isEmpty ? nil : descParts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return (name, ((desc?.isEmpty ?? true) ? nil : desc), body)
    }

    private struct FlowJSON: Decodable {
        struct Param: Decodable { let name: String; let description: String?; let `default`: String?; let exampleValue: String?; let autoDetected: Bool? }
        struct Step: Decodable { let id: Int?; let intent: String?; let inferred: Bool? }
        let parameters: [Param]?
        let steps: [Step]?
    }

    static func parseFlowParameters(_ data: Data) -> [FlowParameter] {
        guard let f = try? JSONDecoder().decode(FlowJSON.self, from: data) else { return [] }
        return (f.parameters ?? []).map {
            FlowParameter(name: $0.name, description: $0.description,
                          defaultValue: $0.default ?? $0.exampleValue, autoDetected: $0.autoDetected ?? false)
        }
    }

    static func parseFlowStepSummaries(_ data: Data) -> [String] {
        guard let f = try? JSONDecoder().decode(FlowJSON.self, from: data) else { return [] }
        return (f.steps ?? []).enumerated().map { i, s in
            let n = s.id ?? (i + 1)
            let intent = s.intent ?? "(step)"
            return (s.inferred == true) ? "\(n). \(intent)  (inferred — verify)" : "\(n). \(intent)"
        }
    }
}
