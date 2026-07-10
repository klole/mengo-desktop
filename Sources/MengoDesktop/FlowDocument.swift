import Foundation

// MARK: - JSONValue

/// A typed, round-trippable JSON value. The synthesizer's `flow.json` carries
/// fields Studio does not understand yet (`manifestId`, `timeRange`, step
/// `evidence`, etc.); decoding to `JSONValue` lets us edit the parts we know
/// about and re-emit everything else unchanged.
indirect enum JSONValue: Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        // Bool before Int — Foundation's JSONDecoder is strict, but order is defensive.
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? c.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unknown JSON value")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:           try c.encodeNil()
        case .bool(let b):    try c.encode(b)
        case .int(let i):     try c.encode(i)
        case .double(let d):  try c.encode(d)
        case .string(let s):  try c.encode(s)
        case .array(let a):   try c.encode(a)
        case .object(let o):  try c.encode(o)
        }
    }
}

extension JSONValue {
    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var boolValue:   Bool?   { if case .bool(let b)   = self { return b }; return nil }
    var intValue:    Int?    { if case .int(let i)    = self { return i }; return nil }
    var arrayValue:  [JSONValue]?         { if case .array(let a)  = self { return a }; return nil }
    var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
    var isNull: Bool { if case .null = self { return true }; return false }
}

// MARK: - FlowDocument

/// In-memory model of a saved skill's `flow.json`. Editing happens here; the
/// raw decoded root and per-step raw dictionaries are kept so that fields
/// Studio doesn't surface (e.g. `evidence`, `manifestId`) survive a Save.
struct FlowDocument: Equatable {

    var slug: String
    var name: String
    var flowDescription: String
    var steps: [Step]
    var parameters: [Parameter]

    /// Raw root object — preserves unknown top-level fields and field values
    /// for fields Studio does not edit (timeRange, narration, etc.).
    fileprivate var root: [String: JSONValue]

    struct Step: Equatable, Identifiable, Hashable {
        /// String form of whatever the source `id` was. `flow.json` ids are
        /// usually slug-like strings ("01_open_chatgpt_atlas") but the schema
        /// historically allowed ints — we normalize to string and remember the
        /// shape so `toJSON()` round-trips it.
        var id: String
        var app: String?
        var intent: String
        var inferred: Bool
        /// User notes (Studio-only). Not part of the synthesizer's output;
        /// gets persisted to `flow.json` as a string field if non-empty.
        var notes: String?
        /// Canvas position in world coordinates. `nil` means "auto-layout" — the
        /// canvas falls back to vertical placement by array index. Only persisted
        /// when explicitly set (so unmodified flows don't churn on first canvas open).
        var position: StepPosition?
        /// Explicit branching targets (step ids). When `nil` the canvas falls
        /// back to a linear edge to the next step in `flow.json`. When non-nil
        /// (including empty array — "this step has no successor"), the linear
        /// default is suppressed.
        var explicitNext: [String]?

        /// Raw step object — preserves `t`, `evidence`, and any other keys.
        fileprivate var raw: [String: JSONValue]
        fileprivate var idWasInt: Bool

        /// Path to the step's evidence screenshot, relative to the skill dir.
        /// Reads `evidence.frame` from the preserved raw object. `nil` if
        /// the step has no frame.
        var frameRelativePath: String? {
            if case .object(let evidence)? = raw["evidence"],
               case .string(let path)? = evidence["frame"], !path.isEmpty {
                return path
            }
            return nil
        }
    }

    /// A point in canvas world space. Stored in `flow.json` as `{"x": …, "y": …}`.
    struct StepPosition: Equatable, Hashable {
        var x: Double
        var y: Double
    }

    /// A parameter declared in `flow.json`. The synthesizer's defaults can be
    /// strings, lists, numbers, or null; we keep the raw `JSONValue` so we
    /// preserve type on save while still showing a friendly string in the UI.
    struct Parameter: Equatable, Identifiable, Hashable {
        var name: String
        var type: String?
        var description: String?
        var defaultValue: JSONValue?
        var autoDetected: Bool

        /// Raw parameter object — preserves `exampleValue` or any other keys.
        fileprivate var raw: [String: JSONValue]
        var id: String { name }

        /// Human-readable representation of `defaultValue`, suitable for both
        /// display and (when the param is a scalar) text-field editing.
        var defaultDisplay: String {
            guard let v = defaultValue else { return "" }
            switch v {
            case .null:           return ""
            case .string(let s):  return s
            case .bool(let b):    return b ? "true" : "false"
            case .int(let i):     return String(i)
            case .double(let d):  return String(d)
            case .array(let a):
                return a.map(Self.scalarDisplay).joined(separator: ", ")
            case .object:
                return (try? String(data: JSONEncoder().encode(v), encoding: .utf8)) ?? ""
            }
        }

        /// True when the default fits in a one-line text field; structured
        /// defaults (lists, objects) get shown read-only as JSON.
        var defaultIsEditableScalar: Bool {
            switch defaultValue {
            case .none, .null, .string, .bool, .int, .double: return true
            case .array, .object: return false
            }
        }

        private static func scalarDisplay(_ v: JSONValue) -> String {
            switch v {
            case .null:          return "null"
            case .string(let s): return s
            case .bool(let b):   return b ? "true" : "false"
            case .int(let i):    return String(i)
            case .double(let d): return String(d)
            case .array, .object:
                return (try? String(data: JSONEncoder().encode(v), encoding: .utf8)) ?? ""
            }
        }
    }
}

// MARK: - Parsing / serialization

enum FlowDocumentError: LocalizedError, Equatable {
    case rootNotAnObject
    case ioFailed(String)

    var errorDescription: String? {
        switch self {
        case .rootNotAnObject: return "flow.json's top level isn't a JSON object."
        case .ioFailed(let m): return m
        }
    }
}

extension FlowDocument {

    init(json: JSONValue) throws {
        guard case .object(let root) = json else { throw FlowDocumentError.rootNotAnObject }
        self.root = root
        self.slug = root["slug"]?.stringValue ?? ""
        self.name = root["name"]?.stringValue ?? ""
        self.flowDescription = root["description"]?.stringValue ?? ""
        if case .array(let arr)? = root["steps"] {
            self.steps = arr.compactMap { Step(json: $0) }
        } else {
            self.steps = []
        }
        if case .array(let arr)? = root["parameters"] {
            self.parameters = arr.compactMap { Parameter(json: $0) }
        } else {
            self.parameters = []
        }
    }

    /// Serializes back to `JSONValue`. Edited fields overwrite their slots in
    /// the preserved root; everything else (parameters, timeRange, …) is
    /// re-emitted verbatim.
    func toJSON() -> JSONValue {
        var r = root
        r["slug"] = .string(slug)
        r["name"] = .string(name)
        r["description"] = .string(flowDescription)
        r["steps"] = .array(steps.map { $0.toJSON() })
        r["parameters"] = .array(parameters.map { $0.toJSON() })
        return .object(r)
    }

    // MARK: file IO

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // sortedKeys gives stable diffs; pretty-printed matches what the
        // synthesizer emits closely enough that the file stays human-readable.
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    private static let decoder = JSONDecoder()

    static func load(from url: URL) throws -> FlowDocument {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch { throw FlowDocumentError.ioFailed("Couldn't read \(url.lastPathComponent): \(error.localizedDescription)") }
        let json: JSONValue
        do { json = try decoder.decode(JSONValue.self, from: data) }
        catch { throw FlowDocumentError.ioFailed("Couldn't parse \(url.lastPathComponent): \(error.localizedDescription)") }
        return try FlowDocument(json: json)
    }

    func save(to url: URL) throws {
        let data: Data
        do { data = try Self.encoder.encode(toJSON()) }
        catch { throw FlowDocumentError.ioFailed("Couldn't encode flow.json: \(error.localizedDescription)") }
        do { try data.write(to: url, options: .atomic) }
        catch { throw FlowDocumentError.ioFailed("Couldn't write \(url.lastPathComponent): \(error.localizedDescription)") }
    }
}

// MARK: - Step

extension FlowDocument.Step {

    init?(json: JSONValue) {
        guard case .object(let raw) = json else { return nil }
        self.raw = raw

        // id: prefer string; fall back to int → string. Skip steps with no id.
        if case .string(let s)? = raw["id"], !s.isEmpty {
            self.id = s
            self.idWasInt = false
        } else if case .int(let i)? = raw["id"] {
            self.id = String(i)
            self.idWasInt = true
        } else {
            return nil
        }

        if case .string(let s)? = raw["app"]    { self.app = s }      else { self.app = nil }
        if case .string(let s)? = raw["intent"] { self.intent = s }   else { self.intent = "" }
        if case .bool(let b)?   = raw["inferred"] { self.inferred = b } else { self.inferred = false }
        if case .string(let s)? = raw["notes"], !s.isEmpty { self.notes = s } else { self.notes = nil }
        // position: accept either {"x": Double, "y": Double} with Int or Double values.
        if case .object(let pos)? = raw["position"],
           let x = pos["x"].flatMap(Self.asDouble),
           let y = pos["y"].flatMap(Self.asDouble) {
            self.position = FlowDocument.StepPosition(x: x, y: y)
        } else {
            self.position = nil
        }
        // explicitNext: array of step-id strings; absence means "auto-linear".
        if case .array(let arr)? = raw["next"] {
            self.explicitNext = arr.compactMap { $0.stringValue }
        } else {
            self.explicitNext = nil
        }
    }

    fileprivate static func asDouble(_ v: JSONValue) -> Double? {
        switch v {
        case .int(let i):    return Double(i)
        case .double(let d): return d
        // Tolerate string-typed coords. The NL-edit prompt asks the model to
        // preserve `position`, but models sometimes quote numbers — we'd rather
        // round-trip the value than silently revert the step to auto-layout.
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default:             return nil
        }
    }

    func toJSON() -> JSONValue {
        var r = raw
        if idWasInt, let i = Int(id) { r["id"] = .int(i) } else { r["id"] = .string(id) }
        if let app, !app.isEmpty { r["app"] = .string(app) } else { r.removeValue(forKey: "app") }
        r["intent"] = .string(intent)
        r["inferred"] = .bool(inferred)
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            r["notes"] = .string(notes)
        } else {
            r.removeValue(forKey: "notes")
        }
        if let p = position {
            r["position"] = .object(["x": .double(p.x), "y": .double(p.y)])
        } else {
            r.removeValue(forKey: "position")
        }
        if let next = explicitNext {
            r["next"] = .array(next.map { .string($0) })
        } else {
            r.removeValue(forKey: "next")
        }
        return .object(r)
    }
}

// MARK: - Canvas helpers

extension FlowDocument {

    /// A directed edge between two steps for canvas rendering.
    struct Edge: Hashable {
        let fromIndex: Int
        let toIndex: Int
        let fromId: String
        let toId: String
        /// `true` when this edge is implied by array order (no explicit `next`),
        /// so the UI can render it differently (e.g. dimmer) and deleting it
        /// just adds `"next": []` to the source step.
        let isImplicit: Bool
    }

    /// Build the edge list. Steps with explicit `next` use those targets; the
    /// rest fall back to a linear edge to the next step in array order (final
    /// step gets no implicit edge). Targets pointing to unknown ids are dropped.
    func edges() -> [Edge] {
        var byId: [String: Int] = [:]
        for (idx, s) in steps.enumerated() { byId[s.id] = idx }
        var result: [Edge] = []
        for (idx, step) in steps.enumerated() {
            if let next = step.explicitNext {
                for targetId in next {
                    guard let toIdx = byId[targetId] else { continue }
                    result.append(.init(fromIndex: idx, toIndex: toIdx,
                                        fromId: step.id, toId: targetId,
                                        isImplicit: false))
                }
            } else if idx + 1 < steps.count {
                let next = steps[idx + 1]
                result.append(.init(fromIndex: idx, toIndex: idx + 1,
                                    fromId: step.id, toId: next.id,
                                    isImplicit: true))
            }
        }
        return result
    }

    /// Auto-layout position for a step at `index` when its `position` is `nil`.
    /// Lays steps out horizontally (left → right) to match the N8N-style
    /// flow direction. Once the user drags, the step persists an explicit
    /// `position` and this fallback is no longer consulted for it.
    static func autoLayoutPosition(forIndex index: Int) -> StepPosition {
        StepPosition(x: Self.autoLayoutOriginX + Double(index) * Self.autoLayoutSpacing,
                     y: Self.autoLayoutOriginY)
    }

    static let autoLayoutOriginX: Double = 120
    static let autoLayoutOriginY: Double = 220
    static let autoLayoutSpacing: Double = 360

    /// Effective canvas position for a step — its explicit `position` if set,
    /// otherwise the auto-layout fallback for its array index. Returns `nil`
    /// for unknown step ids so callers (edge anchors, etc.) skip stale
    /// references instead of silently collapsing them onto step 1.
    func effectivePosition(of stepId: String) -> StepPosition? {
        guard let idx = steps.firstIndex(where: { $0.id == stepId }) else { return nil }
        return steps[idx].position ?? Self.autoLayoutPosition(forIndex: idx)
    }
}

// MARK: - Parameter

extension FlowDocument.Parameter {

    /// Build a fresh parameter (e.g. when the user clicks "Add parameter").
    /// The raw object starts empty; `toJSON()` will fill it from the fields.
    init(name: String, type: String?, description: String?,
         defaultValue: JSONValue?, autoDetected: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.autoDetected = autoDetected
        self.raw = [:]
    }

    init?(json: JSONValue) {
        guard case .object(let raw) = json else { return nil }
        self.raw = raw
        // Drop unnamed params — we can't address them in the UI.
        guard case .string(let name)? = raw["name"], !name.isEmpty else { return nil }
        self.name = name
        if case .string(let s)? = raw["type"] { self.type = s } else { self.type = nil }
        if case .string(let s)? = raw["description"] { self.description = s } else { self.description = nil }
        // `default` is the canonical field; legacy manifests sometimes use `exampleValue`.
        if let d = raw["default"] { self.defaultValue = d }
        else if let d = raw["exampleValue"] { self.defaultValue = d }
        else { self.defaultValue = nil }
        if case .bool(let b)? = raw["autoDetected"] { self.autoDetected = b } else { self.autoDetected = false }
    }

    func toJSON() -> JSONValue {
        var r = raw
        r["name"] = .string(name)
        if let type, !type.isEmpty { r["type"] = .string(type) } else { r.removeValue(forKey: "type") }
        if let description, !description.isEmpty { r["description"] = .string(description) }
        else { r.removeValue(forKey: "description") }
        if let defaultValue { r["default"] = defaultValue }
        else { r.removeValue(forKey: "default") }
        r["autoDetected"] = .bool(autoDetected)
        // If the schema originally used `exampleValue`, drop it so we don't carry two defaults.
        r.removeValue(forKey: "exampleValue")
        return .object(r)
    }

    /// Updates `defaultValue` from a user-edited string. Preserves the original
    /// JSON kind (int/double/bool/null) when round-tripping a scalar — but the
    /// UI only opens this path for scalar parameters (see `defaultIsEditableScalar`).
    mutating func setDefaultFromText(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            defaultValue = (defaultValue == nil) ? nil : .null
            return
        }
        switch defaultValue {
        case .bool:
            if trimmed.lowercased() == "true" { defaultValue = .bool(true) }
            else if trimmed.lowercased() == "false" { defaultValue = .bool(false) }
            else { defaultValue = .string(trimmed) }
        case .int:
            if let i = Int(trimmed) { defaultValue = .int(i) } else { defaultValue = .string(trimmed) }
        case .double:
            if let d = Double(trimmed) { defaultValue = .double(d) } else { defaultValue = .string(trimmed) }
        default:
            defaultValue = .string(trimmed)
        }
    }
}
