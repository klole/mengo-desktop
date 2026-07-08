import XCTest
@testable import ScreenpipeFlow

@MainActor
final class AppStateTests: XCTestCase {
    private func makeState() -> AppState {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenpipeFlowTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return AppState(skillsDir: dir)
    }

    func testInitialStateIsIdle() {
        let state = makeState()
        if case .idle = state.sessionState { return }
        XCTFail("expected .idle, got \(state.sessionState)")
    }

    func testTransitionToBrowsingTimeline() {
        let state = makeState()
        state.beginBrowsingTimeline()
        if case .browsingTimeline = state.sessionState { return }
        XCTFail("expected .browsingTimeline")
    }

    func testTransitionToRecording() {
        let state = makeState()
        let session = RecordingSession(mode: .proactive,
                                       bufferRangeStart: nil,
                                       activeRecordingStart: Date())
        state.beginRecording(session)
        if case .recording = state.sessionState { return }
        XCTFail("expected .recording")
    }

    func testTransitionToSynthesizingPreservesManifest() {
        let state = makeState()
        let url = URL(fileURLWithPath: "/tmp/manifest.json")
        state.beginSynthesizing(manifest: url)
        if case .synthesizing(let m) = state.sessionState {
            XCTAssertEqual(m, url)
        } else {
            XCTFail("expected .synthesizing")
        }
    }

    func testFinalizeReturnsToIdle() {
        let state = makeState()
        state.beginReviewing(skill: URL(fileURLWithPath: "/tmp/skill"))
        state.finalize()
        if case .idle = state.sessionState { return }
        XCTFail("expected .idle after finalize")
    }

    func testAddFlowAppendsToLibrary() {
        let state = makeState()
        let entry = FlowEntry(slug: "foo",
                              name: "Foo",
                              path: URL(fileURLWithPath: "/tmp/foo"),
                              createdAt: Date())
        state.addFlow(entry)
        XCTAssertEqual(state.library.count, 1)
        XCTAssertEqual(state.library.first?.slug, "foo")
    }

    func testAddFlowReplacesExistingWithSameSlug() {
        let state = makeState()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_000_100)
        state.addFlow(FlowEntry(slug: "x", name: "old", path: URL(fileURLWithPath: "/a"), createdAt: earlier))
        state.addFlow(FlowEntry(slug: "x", name: "new", path: URL(fileURLWithPath: "/b"), createdAt: later))
        XCTAssertEqual(state.library.count, 1)
        XCTAssertEqual(state.library.first?.name, "new")
    }

    func testRemoveFlow() {
        let state = makeState()
        state.addFlow(FlowEntry(slug: "a", name: "A",
                                path: URL(fileURLWithPath: "/a"), createdAt: Date()))
        state.addFlow(FlowEntry(slug: "b", name: "B",
                                path: URL(fileURLWithPath: "/b"), createdAt: Date()))
        state.removeFlow(slug: "a")
        XCTAssertEqual(state.library.count, 1)
        XCTAssertEqual(state.library.first?.slug, "b")
    }

    func testLibrarySortedNewestFirst() {
        let state = makeState()
        let earlier = Date(timeIntervalSince1970: 1_700_000_000)
        let later = Date(timeIntervalSince1970: 1_700_000_100)
        state.addFlow(FlowEntry(slug: "old", name: "Old",
                                path: URL(fileURLWithPath: "/o"), createdAt: earlier))
        state.addFlow(FlowEntry(slug: "new", name: "New",
                                path: URL(fileURLWithPath: "/n"), createdAt: later))
        XCTAssertEqual(state.library.map(\.slug), ["new", "old"])
    }
}
