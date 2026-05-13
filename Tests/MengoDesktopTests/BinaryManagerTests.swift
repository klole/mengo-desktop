import XCTest
@testable import MengoDesktop

final class BinaryManagerTests: XCTestCase {

    func test_binaryURL_landsInsideBundledHelpers() {
        XCTAssertTrue(BinaryManager.binaryURL.path.hasSuffix("/Contents/Helpers/screenpipe"),
                      "expected bundled-helper path, got: \(BinaryManager.binaryURL.path)")
    }

    func test_ensureBinary_throwsWhenMissing() {
        // In the test bundle there is no Contents/Helpers/screenpipe, so this must throw.
        XCTAssertThrowsError(try BinaryManager.ensureBinary())
    }
}
