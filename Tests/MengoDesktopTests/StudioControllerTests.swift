import XCTest
@testable import MengoDesktop

@MainActor
final class StudioControllerTests: XCTestCase {

    private static let sampleJSON = """
    {
      "schemaVersion": 1,
      "slug": "test-flow",
      "name": "Test Flow",
      "description": "A test.",
      "steps": [
        { "id": "01", "app": "Mengo", "intent": "do thing", "inferred": false }
      ]
    }
    """

    func test_open_loadsDocumentAndClearsErrors() throws {
        let entry = try makeEntry(slug: "test-flow", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        XCTAssertTrue(studio.open(entry))
        XCTAssertEqual(studio.selectedSlug, "test-flow")
        XCTAssertEqual(studio.document?.name, "Test Flow")
        XCTAssertNil(studio.loadError)
        XCTAssertFalse(studio.isDirty)
    }

    func test_open_invalidJSONSurfacesLoadError() throws {
        let entry = try makeEntry(slug: "broken", flowJSON: "not json")
        let studio = StudioController()
        XCTAssertFalse(studio.open(entry))
        XCTAssertNotNil(studio.loadError)
        XCTAssertNil(studio.document)
        XCTAssertEqual(studio.selectedSlug, "broken") // selection is set so the UI can show Retry
    }

    func test_editingDocument_marksDirty() throws {
        let entry = try makeEntry(slug: "test-flow", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        XCTAssertFalse(studio.isDirty)
        studio.document?.name = "Edited"
        XCTAssertTrue(studio.isDirty)
    }

    func test_discard_restoresPristine() throws {
        let entry = try makeEntry(slug: "test-flow", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.document?.name = "Edited"
        XCTAssertTrue(studio.isDirty)
        studio.discard()
        XCTAssertFalse(studio.isDirty)
        XCTAssertEqual(studio.document?.name, "Test Flow")
    }

    func test_save_writesToDiskAndResetsDirty() throws {
        let entry = try makeEntry(slug: "test-flow", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.document?.steps[0].intent = "after save"
        studio.save(for: entry)
        XCTAssertNil(studio.saveError)
        XCTAssertFalse(studio.isDirty)
        let reloaded = try FlowDocument.load(from: entry.path.appendingPathComponent("flow.json"))
        XCTAssertEqual(reloaded.steps[0].intent, "after save")
    }

    func test_reconcile_dropsSelectionWhenEntryGone() throws {
        let entry = try makeEntry(slug: "test-flow", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        // Library refresh that doesn't include this slug
        studio.reconcile(library: [])
        XCTAssertNil(studio.selectedSlug)
        XCTAssertNil(studio.document)
    }

    func test_close_clearsEverything() throws {
        let entry = try makeEntry(slug: "test-flow", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.close()
        XCTAssertNil(studio.selectedSlug)
        XCTAssertNil(studio.document)
        XCTAssertNil(studio.loadError)
    }

    // MARK: - Reorder

    func test_moveStepDown_movesAndMarksDirty() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        XCTAssertEqual(studio.document?.steps.map(\.id), ["a", "b", "c"])
        XCTAssertTrue(studio.canMoveStepDown(at: 0))
        XCTAssertFalse(studio.canMoveStepUp(at: 0))
        studio.moveStepDown(at: 0)
        XCTAssertEqual(studio.document?.steps.map(\.id), ["b", "a", "c"])
        XCTAssertTrue(studio.isDirty)
    }

    func test_moveStepUp_isInverseOfDown() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.moveStepDown(at: 0)        // [b, a, c]
        studio.moveStepUp(at: 1)          // [a, b, c]
        XCTAssertEqual(studio.document?.steps.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(studio.isDirty)    // back to pristine
    }

    func test_moveStep_outOfRange_isNoOp() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.moveStep(from: 99, to: 0)
        studio.moveStep(from: 0, to: 0)
        XCTAssertFalse(studio.isDirty)
    }

    func test_canMoveStepDown_falseAtLastIndex() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        XCTAssertFalse(studio.canMoveStepDown(at: 2))
        XCTAssertTrue(studio.canMoveStepUp(at: 2))
    }

    // MARK: - Regenerate

    func test_regenerate_successUpdatesStateToSuccess() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.regenerator = { _ in .success(()) }
        await studio.regenerate(for: entry)
        XCTAssertEqual(studio.regenerateState, .success)
    }

    func test_regenerate_failureSurfacesMessage() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        struct Boom: LocalizedError { var errorDescription: String? { "boom" } }
        studio.regenerator = { _ in .failure(Boom()) }
        await studio.regenerate(for: entry)
        if case .failure(let m) = studio.regenerateState { XCTAssertEqual(m, "boom") }
        else { XCTFail("expected .failure, got \(studio.regenerateState)") }
    }

    func test_regenerate_withoutRegenerator_failsWithHelpfulMessage() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        await studio.regenerate(for: entry)
        if case .failure = studio.regenerateState {} else { XCTFail("expected failure") }
    }

    func test_regenerate_dropsResultIfUserSwitchedFlowsMidRun() async throws {
        let entryA = try makeEntry(slug: "a", flowJSON: Self.sampleJSON)
        let entryB = try makeEntry(slug: "b", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entryA)
        // Regenerator that simulates the user switching flows mid-run by
        // calling `open(entryB)` before returning a result for entryA.
        studio.regenerator = { _ in
            _ = studio.open(entryB)
            return .success(())
        }
        await studio.regenerate(for: entryA)
        // The success result belonged to entryA, but selectedSlug is now "b" —
        // state should NOT promote to .success.
        XCTAssertNotEqual(studio.regenerateState, .success)
    }

    func test_save_resetsRegenerateState() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.regenerator = { _ in .success(()) }
        await studio.regenerate(for: entry)
        XCTAssertEqual(studio.regenerateState, .success)
        studio.document?.name = "edited"
        studio.save(for: entry)
        XCTAssertEqual(studio.regenerateState, .idle)
    }

    private static let multiStepJSON = """
    { "steps": [
      { "id": "a", "intent": "A" },
      { "id": "b", "intent": "B" },
      { "id": "c", "intent": "C" }
    ] }
    """

    // MARK: - Canvas mutations

    func test_updateStepPosition_marksDirtyAndSurvivesRoundTrip() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        XCTAssertFalse(studio.isDirty)
        studio.updateStepPosition(id: "a", to: .init(x: 200, y: 300))
        XCTAssertTrue(studio.isDirty)
        XCTAssertEqual(studio.document?.steps[0].position, .init(x: 200, y: 300))
        // Nil reverts to auto-layout.
        studio.updateStepPosition(id: "a", to: nil)
        XCTAssertNil(studio.document?.steps[0].position)
    }

    func test_addEdge_appendsToExplicitNext() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.addEdge(from: "a", to: "c")
        XCTAssertEqual(studio.document?.steps[0].explicitNext, ["c"])
        studio.addEdge(from: "a", to: "b")
        XCTAssertEqual(studio.document?.steps[0].explicitNext, ["c", "b"])
    }

    func test_addEdge_rejectsSelfAndDuplicateAndUnknown() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.addEdge(from: "a", to: "a")           // self-edge ignored
        studio.addEdge(from: "a", to: "ghost")       // unknown target ignored
        studio.addEdge(from: "a", to: "b")
        studio.addEdge(from: "a", to: "b")           // duplicate ignored
        XCTAssertEqual(studio.document?.steps[0].explicitNext, ["b"])
    }

    func test_removeEdge_explicit_removesTarget() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.addEdge(from: "a", to: "c")
        studio.addEdge(from: "a", to: "b")
        studio.removeEdge(from: "a", to: "c")
        XCTAssertEqual(studio.document?.steps[0].explicitNext, ["b"])
    }

    func test_removeEdge_implicit_cutsLinearDefault() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        // Step "a" has no explicitNext yet — its implicit edge is a → b.
        XCTAssertNil(studio.document?.steps[0].explicitNext)
        studio.removeEdge(from: "a", to: "b")
        // Suppressing the linear default is recorded as an empty explicitNext.
        XCTAssertEqual(studio.document?.steps[0].explicitNext, [])
        // The implicit edge is no longer in the edges() output.
        XCTAssertTrue(studio.document?.edges().contains(where: { $0.fromId == "a" }) == false)
    }

    // MARK: - NL edit

    func test_nlEdit_successReloadsDocumentFromDisk() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        XCTAssertEqual(studio.document?.name, "Test Flow")
        // Stub editor rewrites flow.json with a new name, then returns success.
        let url = entry.path.appendingPathComponent("flow.json")
        studio.nlEditor = { _, _, _ in
            let rewritten = """
            { "schemaVersion": 1, "slug": "test-flow", "name": "RENAMED",
              "description": "A test.",
              "steps": [{ "id": "01", "intent": "do thing" }] }
            """
            try? rewritten.write(to: url, atomically: true, encoding: .utf8)
            return .success(())
        }
        await studio.editWithInstruction(for: entry, instruction: "rename it")
        XCTAssertEqual(studio.nlEditState, .success)
        XCTAssertEqual(studio.document?.name, "RENAMED")
        XCTAssertEqual(studio.pristine?.name, "RENAMED")
        XCTAssertFalse(studio.isDirty)
    }

    func test_nlEdit_failureSurfacesMessage() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        struct Boom: LocalizedError { var errorDescription: String? { "model crashed" } }
        studio.nlEditor = { _, _, _ in .failure(Boom()) }
        await studio.editWithInstruction(for: entry, instruction: "do thing")
        if case .failure(let m) = studio.nlEditState { XCTAssertEqual(m, "model crashed") }
        else { XCTFail("expected .failure") }
        // Document not reloaded — still the original.
        XCTAssertEqual(studio.document?.name, "Test Flow")
    }

    func test_nlEdit_withoutEditor_failsWithHelpfulMessage() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        await studio.editWithInstruction(for: entry, instruction: "anything")
        if case .failure = studio.nlEditState {} else { XCTFail("expected failure") }
    }

    func test_nlEdit_dropsResultIfUserSwitchedFlowsMidRun() async throws {
        let entryA = try makeEntry(slug: "a", flowJSON: Self.sampleJSON)
        let entryB = try makeEntry(slug: "b", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entryA)
        studio.nlEditor = { _, _, _ in
            _ = studio.open(entryB)
            return .success(())
        }
        await studio.editWithInstruction(for: entryA, instruction: "rename")
        XCTAssertNotEqual(studio.nlEditState, .success)
    }

    func test_isAsyncRunning_tracksEitherRegenOrNLEdit() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        XCTAssertFalse(studio.isAsyncRunning)
        // Drive nlEditState through the editor closure: it sees .running while
        // awaiting the result, then transitions on completion.
        let saw = expectation(description: "saw running")
        studio.nlEditor = { _, _, _ in
            await MainActor.run {
                XCTAssertTrue(studio.isAsyncRunning)
                saw.fulfill()
            }
            return .success(())
        }
        await studio.editWithInstruction(for: entry, instruction: "x")
        await fulfillment(of: [saw], timeout: 1)
        XCTAssertFalse(studio.isAsyncRunning)
    }

    func test_editWithInstruction_refusesIfBufferIsDirty() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.document?.name = "edited"
        XCTAssertTrue(studio.isDirty)
        var called = false
        studio.nlEditor = { _, _, _ in called = true; return .success(()) }
        await studio.editWithInstruction(for: entry, instruction: "anything")
        XCTAssertFalse(called, "editor should not run with a dirty buffer")
        if case .failure(let m) = studio.nlEditState {
            XCTAssertTrue(m.lowercased().contains("save"), "expected save-first hint, got: \(m)")
        } else { XCTFail("expected .failure") }
    }

    func test_editWithInstruction_restoresBackup_whenModelWritesInvalidJSON() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        let flowURL = entry.path.appendingPathComponent("flow.json")
        let originalBytes = try Data(contentsOf: flowURL)
        // Stub editor overwrites flow.json with garbage, then reports success.
        studio.nlEditor = { _, _, _ in
            try? "not valid json".write(to: flowURL, atomically: true, encoding: .utf8)
            return .success(())
        }
        await studio.editWithInstruction(for: entry, instruction: "break it")
        if case .failure(let m) = studio.nlEditState {
            XCTAssertTrue(m.lowercased().contains("restored"), "expected restore hint, got: \(m)")
        } else { XCTFail("expected .failure") }
        // The on-disk file is the pre-edit backup, byte-for-byte.
        let restored = try Data(contentsOf: flowURL)
        XCTAssertEqual(restored, originalBytes)
        // The in-memory doc still reflects the pre-edit state.
        XCTAssertEqual(studio.document?.name, "Test Flow")
    }

    func test_restoreLinearDefault_clearsExplicitNext() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.multiStepJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        // First suppress a, then restore.
        studio.removeEdge(from: "a", to: "b")
        XCTAssertEqual(studio.document?.steps[0].explicitNext, [])
        studio.restoreLinearDefault(for: "a")
        XCTAssertNil(studio.document?.steps[0].explicitNext)
        // Implicit edge is back.
        XCTAssertTrue(studio.document?.edges().contains(where: { $0.fromId == "a" && $0.toId == "b" && $0.isImplicit }) == true)
    }

    func test_save_resetsBothAsyncStates() async throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        _ = studio.open(entry)
        studio.regenerator = { _ in .success(()) }
        studio.nlEditor = { _, _, _ in .success(()) }
        await studio.regenerate(for: entry)
        XCTAssertEqual(studio.regenerateState, .success)
        // Dirty the doc so save() actually fires.
        studio.document?.name = "edited"
        studio.save(for: entry)
        XCTAssertEqual(studio.regenerateState, .idle)
        XCTAssertEqual(studio.nlEditState, .idle)
    }

    // MARK: - pendingOpen (Library → Studio handoff)

    func test_pendingOpen_propertyExistsAndIsWritable() throws {
        let entry = try makeEntry(slug: "test", flowJSON: Self.sampleJSON)
        let studio = StudioController()
        XCTAssertNil(studio.pendingOpen)
        studio.pendingOpen = entry
        XCTAssertEqual(studio.pendingOpen?.slug, "test")
        studio.pendingOpen = nil
        XCTAssertNil(studio.pendingOpen)
    }

    // MARK: - Helpers

    private func makeEntry(slug: String, flowJSON: String) throws -> FlowEntry {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("studio-test-\(UUID().uuidString)/\(slug)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try flowJSON.write(to: dir.appendingPathComponent("flow.json"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        return FlowEntry(slug: slug, name: slug, path: dir, createdAt: Date(), sourceManifestId: nil)
    }
}
