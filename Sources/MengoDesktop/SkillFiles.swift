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
                name = decodedScalar(String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)); inDesc = false
            } else if let r = raw.range(of: #"^\s*description\s*:\s*"#, options: .regularExpression) {
                descParts = [String(raw[r.upperBound...]).trimmingCharacters(in: .whitespaces)]; inDesc = true
            } else if inDesc, raw.first == " " || raw.first == "\t" {
                descParts.append(raw.trimmingCharacters(in: .whitespaces))
            } else {
                inDesc = false
            }
        }
        let body = String(lines[(closeIdx + 1)...].joined(separator: "\n").drop(while: { $0 == "\n" }))
        let desc = descParts.isEmpty ? nil : decodedScalar(descParts.joined(separator: " ").trimmingCharacters(in: .whitespaces))
        return (name, ((desc?.isEmpty ?? true) ? nil : desc), body)
    }

    private static func decodedScalar(_ value: String) -> String {
        guard value.first == "\"", value.last == "\"",
              let data = value.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(String.self, from: data) else { return value }
        return decoded
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

    /// Applies the edits from the Review screen to both canonical skill files.
    /// Unknown flow.json fields survive through `FlowDocument`'s round-trip.
    static func applyReviewEdits(skillDir: URL,
                                 slug: String,
                                 name: String,
                                 description: String?,
                                 parameters: [FlowParameter]) throws {
        let flowURL = skillDir.appendingPathComponent("flow.json")
        var document = try FlowDocument.load(from: flowURL)
        document.slug = slug
        document.name = name
        document.flowDescription = description ?? ""

        let existingByName = Dictionary(uniqueKeysWithValues: document.parameters.map { ($0.name, $0) })
        document.parameters = parameters.map { edited in
            var parameter = existingByName[edited.name] ?? FlowDocument.Parameter(
                name: edited.name, type: "string", description: edited.description,
                defaultValue: nil, autoDetected: edited.autoDetected)
            parameter.name = edited.name
            parameter.description = edited.description
            parameter.autoDetected = edited.autoDetected
            if let value = edited.defaultValue { parameter.setDefaultFromText(value) }
            else { parameter.defaultValue = nil }
            return parameter
        }
        try document.save(to: flowURL)

        let skillURL = skillDir.appendingPathComponent("SKILL.md")
        let current = try String(contentsOf: skillURL, encoding: .utf8)
        let parsed = parseSkillMarkdown(current)
        let body = replacingParametersSection(in: parsed.body, parameters: parameters)
        let markdown = """
        ---
        name: \(yamlQuoted(name))
        description: \(yamlQuoted(description ?? ""))
        ---

        \(body)
        """
        try markdown.write(to: skillURL, atomically: true, encoding: .utf8)
    }

    private static func replacingParametersSection(in body: String,
                                                    parameters: [FlowParameter]) -> String {
        var lines = body.components(separatedBy: "\n")
        let section = parameterSection(parameters).components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "## Parameters" }) {
            let end = lines[(start + 1)...].firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("## ")
            }) ?? lines.endIndex
            lines.replaceSubrange(start..<end, with: section + [""])
        } else if let steps = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "## Steps"
        }) {
            lines.insert(contentsOf: section + [""], at: steps)
        } else {
            if lines.last?.isEmpty == false { lines.append("") }
            lines.append(contentsOf: section)
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func parameterSection(_ parameters: [FlowParameter]) -> String {
        guard !parameters.isEmpty else { return "## Parameters\n\nNone." }
        let rows = parameters.map { parameter in
            var detail = parameter.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if let value = parameter.defaultValue, !value.isEmpty {
                detail += detail.isEmpty ? "Default: `\(markdownEscaped(value))`." : " Default: `\(markdownEscaped(value))`."
            }
            return "- `{{\(markdownEscaped(parameter.name))}}`" + (detail.isEmpty ? "" : ": \(detail)")
        }
        return "## Parameters\n\n" + rows.joined(separator: "\n")
    }

    private static func yamlQuoted(_ value: String) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let quoted = String(data: data, encoding: .utf8) else { return "\"\"" }
        return quoted
    }

    private static func markdownEscaped(_ value: String) -> String {
        value.replacingOccurrences(of: "`", with: "\\`")
    }
}
