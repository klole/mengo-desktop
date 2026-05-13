import XCTest
@testable import MengoDesktop

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "settings-\(UUID().uuidString)")! }
    final class StubLoginItem: LoginItemControlling, @unchecked Sendable {
        var enabled = false; var failOnRegister = false
        func register() throws { if failOnRegister { throw NSError(domain: "x", code: 1) }; enabled = true }
        func unregister() throws { enabled = false }
        var isEnabled: Bool { enabled }
    }
    func test_defaults() {
        let s = SettingsStore(defaults: defaults(), loginItem: StubLoginItem())
        XCTAssertEqual(s.synthesisRuntime, .claudeCode)
        XCTAssertTrue(s.startRecordingOnLaunch)
        XCTAssertFalse(s.openAtLogin)
    }
    func test_persistsRuntimeAndStartFlag() {
        let d = defaults()
        let s1 = SettingsStore(defaults: d, loginItem: StubLoginItem())
        s1.synthesisRuntime = .codex; s1.startRecordingOnLaunch = false
        let s2 = SettingsStore(defaults: d, loginItem: StubLoginItem())
        XCTAssertEqual(s2.synthesisRuntime, .codex)
        XCTAssertFalse(s2.startRecordingOnLaunch)
    }
    func test_openAtLogin_togglesBackend() {
        let li = StubLoginItem()
        let s = SettingsStore(defaults: defaults(), loginItem: li)
        s.openAtLogin = true; XCTAssertTrue(li.isEnabled); XCTAssertTrue(s.openAtLogin)
        s.openAtLogin = false; XCTAssertFalse(li.isEnabled)
    }
    func test_openAtLogin_registerFailure_setsErrorAndReverts() {
        let li = StubLoginItem(); li.failOnRegister = true
        let s = SettingsStore(defaults: defaults(), loginItem: li)
        s.openAtLogin = true
        XCTAssertFalse(s.openAtLogin); XCTAssertNotNil(s.loginItemError)
    }
}
