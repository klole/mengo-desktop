import XCTest
@testable import MengoDesktop

final class SourceCatalogTests: XCTestCase {

    func test_decodeMonitors_parsesData() throws {
        let json = Data("""
        { "data": [
            { "id": 1, "name": "Display 1", "width": 1728, "height": 1117, "is_default": true },
            { "id": 2, "name": "Display 2", "width": 3440, "height": 1440, "is_default": false }
        ], "success": true }
        """.utf8)
        let monitors = try SourceCatalog.decodeMonitors(from: json)
        XCTAssertEqual(monitors.count, 2)
        XCTAssertEqual(monitors[0].id, 1)
        XCTAssertEqual(monitors[0].name, "Display 1")
        XCTAssertEqual(monitors[0].width, 1728)
        XCTAssertEqual(monitors[0].height, 1117)
        XCTAssertTrue(monitors[0].isDefault)
        XCTAssertFalse(monitors[1].isDefault)
    }

    func test_decodeAudioDevices_parsesKindAndDisplayName() throws {
        let json = Data("""
        { "data": [
            { "name": "MacBook Pro Microphone (input)", "is_default": false },
            { "name": "System Audio (output)", "is_default": true },
            { "name": "Weird Device", "is_default": false }
        ], "success": true }
        """.utf8)
        let devices = try SourceCatalog.decodeAudioDevices(from: json)
        XCTAssertEqual(devices.count, 3)
        XCTAssertEqual(devices[0].name, "MacBook Pro Microphone (input)")
        XCTAssertEqual(devices[0].displayName, "MacBook Pro Microphone")
        XCTAssertEqual(devices[0].kind, .input)
        XCTAssertEqual(devices[1].displayName, "System Audio")
        XCTAssertEqual(devices[1].kind, .output)
        XCTAssertTrue(devices[1].isDefault)
        XCTAssertEqual(devices[2].displayName, "Weird Device")
        XCTAssertEqual(devices[2].kind, .unknown)
    }

    func test_decode_throwsOnMalformedBody() {
        XCTAssertThrowsError(try SourceCatalog.decodeMonitors(from: Data("not json".utf8)))
        XCTAssertThrowsError(try SourceCatalog.decodeAudioDevices(from: Data(#"{"success":true}"#.utf8)))
    }

    func test_cliCatalog_throwsOnNonZeroExit() async throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("failing-screenpipe-\(UUID().uuidString).sh")
        try """
        #!/usr/bin/env bash
        echo "permission denied" >&2
        exit 7
        """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let catalog = ScreenpipeCLICatalog(binaryURL: { script })
        do {
            _ = try await catalog.availableMonitors()
            XCTFail("expected command failure")
        } catch let error as SourceCatalog.CLIError {
            XCTAssertEqual(error, .commandFailed(args: ["vision", "list", "-o", "json"], status: 7, stderr: "permission denied"))
            XCTAssertTrue(error.description.contains("permission denied"))
        }
    }
}
