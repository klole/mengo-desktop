import XCTest
@testable import MengoDesktop

/// CaptureMode is a pure value type. The bundled recorder currently does not
/// expose a supported frame-rate flag, so modes must not emit unsupported CLI
/// arguments.
@MainActor
final class CaptureModeTests: XCTestCase {

    func test_smartCapture_emitsNoUnsupportedFlags() {
        XCTAssertEqual(CaptureMode.smartCapture.recorderFlags, [])
    }

    func test_allChanges_emitsNoUnsupportedFlags() {
        XCTAssertEqual(CaptureMode.allChanges.recorderFlags, [])
    }

    func test_periodic_emitsNoUnsupportedFlags() {
        XCTAssertEqual(CaptureMode.periodic.recorderFlags, [])
    }

    func test_persistsAndRestoresFromUserDefaults() {
        let suite = "MengoTest-CaptureMode-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let stub = StubLoginItem()
        let s1 = SettingsStore(defaults: defaults, loginItem: stub)
        XCTAssertEqual(s1.captureMode, .smartCapture, "default is Smart Capture")

        s1.captureMode = .periodic

        let s2 = SettingsStore(defaults: defaults, loginItem: stub)
        XCTAssertEqual(s2.captureMode, .periodic, "selection persists across SettingsStore instances")
    }
}

private struct StubLoginItem: LoginItemControlling {
    func register() throws {}
    func unregister() throws {}
    var isEnabled: Bool { false }
}
