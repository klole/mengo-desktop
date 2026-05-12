import XCTest
@testable import ScreenpipeMenu

final class BinaryManagerTests: XCTestCase {

    func testBinaryURLLandsInsideBundledHelpers() {
        let path = BinaryManager.binaryURL.path
        XCTAssertTrue(path.hasSuffix("/Contents/Helpers/screenpipe"),
                      "expected bundled-helper path, got: \(path)")
    }
}
