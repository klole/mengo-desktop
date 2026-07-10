import XCTest
@testable import MengoDesktop

final class FlowDocumentTests: XCTestCase {

    // MARK: - JSONValue round-trip

    func test_jsonValue_roundTrip_preservesAllFieldsAndTypes() throws {
        let original: JSONValue = .object([
            "schemaVersion": .int(1),
            "name": .string("My Flow"),
            "description": .string("does a thing"),
            "active": .bool(true),
            "ratio": .double(0.75),
            "tags": .array([.string("a"), .string("b")]),
            "nested": .object(["k": .string("v")]),
            "missing": .null,
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Parsing

    private static let realFlowJSON = """
    {
      "schemaVersion": 1,
      "slug": "redesign-recording-popup",
      "name": "Redesign the Mengo Desktop recording popup",
      "description": "Redesign the popup that appears on the Flow page.",
      "mode": "proactive",
      "manifestId": "ABC-123",
      "timeRange": { "start": "2026-05-15T01:58:42Z", "end": "2026-05-15T02:00:22Z" },
      "parameters": [
        { "name": "target", "type": "string", "default": "popup",
          "description": "what we're redesigning", "autoDetected": false }
      ],
      "steps": [
        { "id": "01_open", "t": "2026-05-15T01:58:47Z", "app": "Atlas",
          "intent": "Open a fresh prompt.",
          "evidence": { "frame": "frames/01.png", "ocr": "raw text" },
          "inferred": false },
        { "id": "02_redesign", "t": null, "app": "Mengo Desktop",
          "intent": "Apply the redesign.", "evidence": null, "inferred": true }
      ],
      "frames": ["frames/01.png"]
    }
    """

    func test_parse_extractsNameDescriptionAndSteps() throws {
        let data = Data(Self.realFlowJSON.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let doc = try FlowDocument(json: json)
        XCTAssertEqual(doc.name, "Redesign the Mengo Desktop recording popup")
        XCTAssertEqual(doc.flowDescription, "Redesign the popup that appears on the Flow page.")
        XCTAssertEqual(doc.steps.count, 2)
        XCTAssertEqual(doc.steps[0].id, "01_open")
        XCTAssertEqual(doc.steps[0].app, "Atlas")
        XCTAssertEqual(doc.steps[0].intent, "Open a fresh prompt.")
        XCTAssertFalse(doc.steps[0].inferred)
        XCTAssertNil(doc.steps[0].notes)
        XCTAssertEqual(doc.steps[1].id, "02_redesign")
        XCTAssertTrue(doc.steps[1].inferred)
    }

    func test_parse_rejectsNonObjectRoot() {
        XCTAssertThrowsError(try FlowDocument(json: .array([]))) { error in
            XCTAssertEqual(error as? FlowDocumentError, .rootNotAnObject)
        }
    }

    func test_parse_intStepIdIsNormalizedToString() throws {
        let data = Data(#"{ "steps": [ {"id": 7, "intent": "x"} ] }"#.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let doc = try FlowDocument(json: json)
        XCTAssertEqual(doc.steps.first?.id, "7")
    }

    func test_parse_skipsStepsWithoutId() throws {
        let data = Data(#"{ "steps": [ {"intent": "no id"}, {"id": "ok", "intent": "yes"} ] }"#.utf8)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        let doc = try FlowDocument(json: json)
        XCTAssertEqual(doc.steps.map(\.id), ["ok"])
    }

    // MARK: - Edit and save round-trip

    func test_save_preservesUnknownTopLevelAndStepFields() throws {
        let url = makeTempFlowJSON(Self.realFlowJSON)
        var doc = try FlowDocument.load(from: url)
        doc.name = "Renamed"
        doc.steps[0].intent = "Updated intent"
        try doc.save(to: url)

        let reloaded = try Data(contentsOf: url)
        let root = try JSONDecoder().decode(JSONValue.self, from: reloaded)
        guard case .object(let r) = root else { return XCTFail("not an object") }

        // Edited fields took effect.
        XCTAssertEqual(r["name"]?.stringValue, "Renamed")
        guard case .array(let steps)? = r["steps"], case .object(let s0) = steps[0] else { return XCTFail("steps shape lost") }
        XCTAssertEqual(s0["intent"]?.stringValue, "Updated intent")

        // Unknown top-level fields preserved verbatim.
        XCTAssertEqual(r["schemaVersion"]?.intValue, 1)
        XCTAssertEqual(r["slug"]?.stringValue, "redesign-recording-popup")
        XCTAssertEqual(r["mode"]?.stringValue, "proactive")
        XCTAssertEqual(r["manifestId"]?.stringValue, "ABC-123")
        XCTAssertNotNil(r["timeRange"])
        XCTAssertNotNil(r["parameters"])
        XCTAssertNotNil(r["frames"])

        // Per-step unknown fields preserved.
        XCTAssertEqual(s0["t"]?.stringValue, "2026-05-15T01:58:47Z")
        XCTAssertEqual(s0["app"]?.stringValue, "Atlas")
        guard case .object(let evidence)? = s0["evidence"] else { return XCTFail("evidence dropped") }
        XCTAssertEqual(evidence["frame"]?.stringValue, "frames/01.png")
        XCTAssertEqual(evidence["ocr"]?.stringValue, "raw text")
    }

    func test_save_writesInferredAndNotesEdits() throws {
        let url = makeTempFlowJSON(Self.realFlowJSON)
        var doc = try FlowDocument.load(from: url)
        doc.steps[0].inferred = true
        doc.steps[0].notes = "double-check this"
        try doc.save(to: url)

        let reloaded = try FlowDocument.load(from: url)
        XCTAssertTrue(reloaded.steps[0].inferred)
        XCTAssertEqual(reloaded.steps[0].notes, "double-check this")
    }

    func test_save_strippsEmptyNotesAndEmptyApp() throws {
        let url = makeTempFlowJSON(Self.realFlowJSON)
        var doc = try FlowDocument.load(from: url)
        doc.steps[0].notes = "  " // whitespace only
        doc.steps[0].app = ""
        try doc.save(to: url)

        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard case .object(let r) = json, case .array(let steps)? = r["steps"],
              case .object(let s0) = steps[0] else { return XCTFail("shape lost") }
        XCTAssertNil(s0["notes"])
        XCTAssertNil(s0["app"])
    }

    func test_save_intIdPreservedAsInt() throws {
        let url = makeTempFlowJSON(#"{ "steps": [ {"id": 7, "intent": "x"} ] }"#)
        var doc = try FlowDocument.load(from: url)
        doc.steps[0].intent = "y"
        try doc.save(to: url)

        let json = try JSONDecoder().decode(JSONValue.self, from: try Data(contentsOf: url))
        guard case .object(let r) = json, case .array(let steps)? = r["steps"],
              case .object(let s0) = steps[0] else { return XCTFail("shape lost") }
        XCTAssertEqual(s0["id"]?.intValue, 7)
    }

    // MARK: - Parameters

    func test_parse_parametersRoundTripStringListNull() throws {
        let json = """
        { "parameters": [
          { "name": "target", "type": "string", "default": "popup", "description": "what", "autoDetected": false },
          { "name": "clutter", "type": "list", "default": ["a", "b"], "autoDetected": true },
          { "name": "mockup", "type": "path", "default": null, "autoDetected": false }
        ] }
        """
        let url = makeTempFlowJSON(json)
        let doc = try FlowDocument.load(from: url)
        XCTAssertEqual(doc.parameters.count, 3)
        XCTAssertEqual(doc.parameters[0].name, "target")
        XCTAssertEqual(doc.parameters[0].type, "string")
        XCTAssertEqual(doc.parameters[0].defaultDisplay, "popup")
        XCTAssertTrue(doc.parameters[0].defaultIsEditableScalar)
        XCTAssertEqual(doc.parameters[1].defaultDisplay, "a, b")
        XCTAssertFalse(doc.parameters[1].defaultIsEditableScalar) // list — read-only
        XCTAssertTrue(doc.parameters[1].autoDetected)
        XCTAssertEqual(doc.parameters[2].defaultDisplay, "")
        XCTAssertTrue(doc.parameters[2].defaultIsEditableScalar) // null counts as scalar
    }

    func test_save_parametersPreservesUnknownFieldsAndTypes() throws {
        // exampleValue is a legacy alias the parser falls back to.
        let json = """
        { "parameters": [
          { "name": "p", "type": "string", "exampleValue": "x", "extra": "keep me" }
        ] }
        """
        let url = makeTempFlowJSON(json)
        var doc = try FlowDocument.load(from: url)
        doc.parameters[0].description = "now described"
        try doc.save(to: url)

        let reloaded = try Data(contentsOf: url)
        let json2 = try JSONDecoder().decode(JSONValue.self, from: reloaded)
        guard case .object(let r) = json2, case .array(let ps)? = r["parameters"],
              case .object(let p0) = ps[0] else { return XCTFail("shape lost") }
        XCTAssertEqual(p0["description"]?.stringValue, "now described")
        XCTAssertEqual(p0["default"]?.stringValue, "x")
        XCTAssertNil(p0["exampleValue"]) // legacy alias dropped
        XCTAssertEqual(p0["extra"]?.stringValue, "keep me")
    }

    func test_parameter_setDefaultFromText_preservesScalarKinds() throws {
        var p = FlowDocument.Parameter(name: "n", type: "int", description: nil,
                                       defaultValue: .int(5), autoDetected: false)
        p.setDefaultFromText("42")
        XCTAssertEqual(p.defaultValue, .int(42))
        p.setDefaultFromText("nope")
        XCTAssertEqual(p.defaultValue, .string("nope")) // graceful demotion
        var b = FlowDocument.Parameter(name: "b", type: "bool", description: nil,
                                       defaultValue: .bool(true), autoDetected: false)
        b.setDefaultFromText("false")
        XCTAssertEqual(b.defaultValue, .bool(false))
    }

    // MARK: - Step.frameRelativePath

    func test_step_frameRelativePath_readsEvidenceFrame() throws {
        let url = makeTempFlowJSON(Self.realFlowJSON)
        let doc = try FlowDocument.load(from: url)
        XCTAssertEqual(doc.steps[0].frameRelativePath, "frames/01.png")
        XCTAssertNil(doc.steps[1].frameRelativePath) // evidence is null
    }

    // MARK: - Canvas: position + explicitNext round-trip

    func test_step_positionRoundTripsAsDouble() throws {
        let json = """
        { "steps": [
          { "id": "a", "intent": "A", "position": { "x": 120.5, "y": 80 } },
          { "id": "b", "intent": "B" }
        ] }
        """
        let url = makeTempFlowJSON(json)
        var doc = try FlowDocument.load(from: url)
        XCTAssertEqual(doc.steps[0].position, .init(x: 120.5, y: 80))
        XCTAssertNil(doc.steps[1].position)
        doc.steps[1].position = .init(x: 50, y: 200)
        try doc.save(to: url)
        let reloaded = try FlowDocument.load(from: url)
        XCTAssertEqual(reloaded.steps[1].position, .init(x: 50, y: 200))
    }

    func test_step_explicitNext_roundTripsAndSuppressesLinearDefault() throws {
        let json = """
        { "steps": [
          { "id": "a", "intent": "A", "next": ["c"] },
          { "id": "b", "intent": "B" },
          { "id": "c", "intent": "C", "next": [] }
        ] }
        """
        let url = makeTempFlowJSON(json)
        let doc = try FlowDocument.load(from: url)
        XCTAssertEqual(doc.steps[0].explicitNext, ["c"])
        XCTAssertNil(doc.steps[1].explicitNext)        // default linear
        XCTAssertEqual(doc.steps[2].explicitNext, [])  // empty list — terminator
        let edges = doc.edges()
        // a → c (explicit), b → c (implicit linear), c → (none, explicit empty)
        XCTAssertEqual(edges.count, 2)
        XCTAssertEqual(edges[0].fromId, "a"); XCTAssertEqual(edges[0].toId, "c"); XCTAssertFalse(edges[0].isImplicit)
        XCTAssertEqual(edges[1].fromId, "b"); XCTAssertEqual(edges[1].toId, "c"); XCTAssertTrue(edges[1].isImplicit)
    }

    func test_edges_ignoresUnknownTargets() throws {
        let json = """
        { "steps": [
          { "id": "a", "intent": "A", "next": ["ghost"] }
        ] }
        """
        let url = makeTempFlowJSON(json)
        let doc = try FlowDocument.load(from: url)
        XCTAssertEqual(doc.edges(), [])
    }

    func test_position_acceptsStringTypedCoords() throws {
        // Some models quote numbers in JSON output. We'd rather round-trip the
        // value than silently revert to auto-layout (which would then clobber
        // the model's intent on the next user drag).
        let json = """
        { "steps": [
          { "id": "a", "intent": "A", "position": { "x": "120.5", "y": "80" } }
        ] }
        """
        let url = makeTempFlowJSON(json)
        let doc = try FlowDocument.load(from: url)
        XCTAssertEqual(doc.steps[0].position, .init(x: 120.5, y: 80))
    }

    func test_effectivePosition_returnsNilForUnknownSlug() throws {
        let url = makeTempFlowJSON(Self.realFlowJSON)
        let doc = try FlowDocument.load(from: url)
        XCTAssertNotNil(doc.effectivePosition(of: "01_open"))
        XCTAssertNil(doc.effectivePosition(of: "ghost-step"))
    }

    func test_save_preservesLinearDefaultWhenExplicitNextIsNil() throws {
        let json = #"{ "steps": [ {"id": "a", "intent": "A"}, {"id": "b", "intent": "B"} ] }"#
        let url = makeTempFlowJSON(json)
        var doc = try FlowDocument.load(from: url)
        doc.steps[0].intent = "edited"
        try doc.save(to: url)
        let raw = try Data(contentsOf: url)
        let v = try JSONDecoder().decode(JSONValue.self, from: raw)
        guard case .object(let r) = v, case .array(let steps)? = r["steps"],
              case .object(let s0) = steps[0] else { return XCTFail("shape lost") }
        // explicitNext was nil → no "next" key in output (preserves linear default).
        XCTAssertNil(s0["next"])
    }

    // MARK: - Helpers

    private func makeTempFlowJSON(_ content: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flow-doc-test-\(UUID().uuidString).json")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
