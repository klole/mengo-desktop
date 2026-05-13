import XCTest
@testable import MengoDesktop

final class FlowLibraryTests: XCTestCase {
    private func tmpFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("flowlib-\(UUID().uuidString)")
            .appendingPathComponent("library.json")
    }

    func test_empty_whenFileMissing() {
        XCTAssertEqual(FlowLibrary(fileURL: tmpFile()).load(), [])
    }

    func test_add_thenLoad_roundTrips_newestFirst() {
        let lib = FlowLibrary(fileURL: tmpFile())
        let early = Date(timeIntervalSince1970: 1_700_000_000)
        let late  = Date(timeIntervalSince1970: 1_700_000_100)
        lib.add(FlowEntry(slug: "old", name: "Old", path: URL(fileURLWithPath: "/a"), createdAt: early, sourceManifestId: "m1"))
        lib.add(FlowEntry(slug: "new", name: "New", path: URL(fileURLWithPath: "/b"), createdAt: late,  sourceManifestId: "m2"))
        XCTAssertEqual(lib.load().map(\.slug), ["new", "old"])
        XCTAssertEqual(lib.load().first?.name, "New")
    }

    func test_add_replacesSameSlug() {
        let lib = FlowLibrary(fileURL: tmpFile())
        lib.add(FlowEntry(slug: "x", name: "old", path: URL(fileURLWithPath: "/a"), createdAt: Date(timeIntervalSince1970: 1), sourceManifestId: nil))
        lib.add(FlowEntry(slug: "x", name: "new", path: URL(fileURLWithPath: "/b"), createdAt: Date(timeIntervalSince1970: 2), sourceManifestId: nil))
        XCTAssertEqual(lib.load().count, 1)
        XCTAssertEqual(lib.load().first?.name, "new")
    }

    func test_remove() {
        let lib = FlowLibrary(fileURL: tmpFile())
        lib.add(FlowEntry(slug: "a", name: "A", path: URL(fileURLWithPath: "/a"), createdAt: Date(), sourceManifestId: nil))
        lib.add(FlowEntry(slug: "b", name: "B", path: URL(fileURLWithPath: "/b"), createdAt: Date(), sourceManifestId: nil))
        lib.remove(slug: "a")
        XCTAssertEqual(lib.load().map(\.slug), ["b"])
    }

    func test_persistsAcrossInstances() {
        let url = tmpFile()
        FlowLibrary(fileURL: url).add(FlowEntry(slug: "z", name: "Z", path: URL(fileURLWithPath: "/z"), createdAt: Date(), sourceManifestId: "m"))
        XCTAssertEqual(FlowLibrary(fileURL: url).load().map(\.slug), ["z"])
    }
}
