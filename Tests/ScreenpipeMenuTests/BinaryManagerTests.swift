import XCTest
@testable import ScreenpipeMenu

final class BinaryManagerTests: XCTestCase {

    func testArchDetectionReturnsArm64OrX64() {
        let arch = BinaryManager.currentArch()
        XCTAssertTrue(arch == "arm64" || arch == "x64", "unexpected arch: \(arch)")
    }

    func testTarballURLForArm64() {
        let url = BinaryManager.tarballURL(version: "0.3.327", arch: "arm64")
        XCTAssertEqual(
            url.absoluteString,
            "https://registry.npmjs.org/@screenpipe/cli-darwin-arm64/-/cli-darwin-arm64-0.3.327.tgz"
        )
    }

    func testTarballURLForX64() {
        let url = BinaryManager.tarballURL(version: "0.3.327", arch: "x64")
        XCTAssertEqual(
            url.absoluteString,
            "https://registry.npmjs.org/@screenpipe/cli-darwin-x64/-/cli-darwin-x64-0.3.327.tgz"
        )
    }

    func testVersionParseExtractsLatestField() throws {
        let json = #"{"name":"screenpipe","version":"0.3.327","other":"ignored"}"#
        let data = json.data(using: .utf8)!
        let version = try BinaryManager.parseLatestVersion(from: data)
        XCTAssertEqual(version, "0.3.327")
    }

    func testVersionParseThrowsOnMissingField() {
        let data = #"{"name":"screenpipe"}"#.data(using: .utf8)!
        XCTAssertThrowsError(try BinaryManager.parseLatestVersion(from: data))
    }
}
