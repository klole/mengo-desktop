import XCTest
@testable import MengoDesktop

/// CaptureMode is a pure value type — its only job is to map a high-level
/// mode onto a stable set of recorder CLI flags. Test that directly so the
/// flag table is locked down and accidental regressions show up in CI.
@MainActor
final class CaptureModeTests: XCTestCase {

    func test_smartCapture_setsOneFpsChangeDetected() {
        XCTAssertEqual(CaptureMode.smartCapture.recorderFlags, ["--fps", "1.0"])
    }

    func test_allChanges_setsTwoFps() {
        XCTAssertEqual(CaptureMode.allChanges.recorderFlags, ["--fps", "2.0"])
    }

    func test_periodic_setsHalfFps() {
        XCTAssertEqual(CaptureMode.periodic.recorderFlags, ["--fps", "0.5"])
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
