import Foundation
import Observation
import ServiceManagement

/// The "open at login" backend, abstracted for tests.
protocol LoginItemControlling: Sendable {
    func register() throws
    func unregister() throws
    var isEnabled: Bool { get }
}

struct SMLoginItem: LoginItemControlling {
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
}

/// User preferences: synthesis runtime, startup behaviour, login item.
/// `synthesisRuntime` and `startRecordingOnLaunch` persist to `UserDefaults`;
/// `openAtLogin` mirrors `SMAppService.mainApp` (the system is the source of truth).
@Observable
@MainActor
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let loginItem: LoginItemControlling
    private(set) var loginItemError: String?

    var synthesisRuntime: SynthesisRuntime {
        didSet { defaults.set(synthesisRuntime.rawValue, forKey: Keys.runtime) }
    }
    var startRecordingOnLaunch: Bool {
        didSet { defaults.set(startRecordingOnLaunch, forKey: Keys.startRec) }
    }
    var topAppsWindow: TopAppsWindow {
        didSet { defaults.set(topAppsWindow.rawValue, forKey: Keys.topAppsWindow) }
    }

    private enum Keys {
        static let runtime = "synthesisRuntime"
        static let startRec = "startRecordingOnLaunch"
        static let topAppsWindow = "topAppsWindow"
    }

    init(defaults: UserDefaults = .standard, loginItem: LoginItemControlling = SMLoginItem()) {
        self.defaults = defaults
        self.loginItem = loginItem
        self.synthesisRuntime = (defaults.string(forKey: Keys.runtime)).flatMap(SynthesisRuntime.init(rawValue:)) ?? .claudeCode
        self.startRecordingOnLaunch = defaults.object(forKey: Keys.startRec) as? Bool ?? true
        self.topAppsWindow = (defaults.string(forKey: Keys.topAppsWindow)).flatMap(TopAppsWindow.init(rawValue:)) ?? .today
        AppDelegate.sharedSettings = self
    }

    var openAtLogin: Bool {
        get { loginItem.isEnabled }
        set {
            loginItemError = nil
            do {
                try newValue ? loginItem.register() : loginItem.unregister()
            } catch {
                loginItemError = "Couldn't \(newValue ? "enable" : "disable") launch-at-login — move Mengo Desktop to your Applications folder and try again."
            }
        }
    }
}
