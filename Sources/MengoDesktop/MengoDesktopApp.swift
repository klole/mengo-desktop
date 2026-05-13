import SwiftUI
import AppKit
import UserNotifications

extension Notification.Name {
    /// Posted by the ⌃⌥G global hotkey; observed by the menu-bar label to raise
    /// the main window onto the Flow tab and open the "grab last N minutes" picker.
    static let openFlowTimeline = Notification.Name("MengoDesktop.openFlowTimeline")
}

@main
@MainActor
struct MengoDesktopApp: App {
    @State private var appState = AppState()
    @State private var account: AccountStore
    @State private var settings: SettingsStore
    @State private var recorder: RecorderController
    @State private var hud: RecordingHUDController
    @State private var hotkeys: HotkeyManager
    @State private var flow: FlowController
    @Environment(\.openWindow) private var openWindow
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Log.bootstrap()
        let acct = AccountStore()
        let st = SettingsStore()
        let rec = RecorderController()
        let h = RecordingHUDController()
        let hk = HotkeyManager()
        let fl = FlowController.live(recorder: rec, hud: h, account: acct, settings: st, notify: { AppDelegate.postFlowNotification($0) })
        _account = State(initialValue: acct)
        _settings = State(initialValue: st)
        _recorder = State(initialValue: rec)
        _hud = State(initialValue: h)
        _hotkeys = State(initialValue: hk)
        _flow = State(initialValue: fl)
        AppDelegate.sharedHotkeys = hk
    }

    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            Group {
                if case .signedIn = account.state {
                    MainWindowView(appState: appState, recorder: recorder, account: account, settings: settings, flow: flow)
                } else {
                    SignInView(account: account)
                }
            }
            .onOpenURL { url in
                guard let link = MengoURL.parse(url) else { Log.line("ignored deep link: \(url)"); return }
                Task { @MainActor in
                    switch link {
                    case .auth(let token):
                        await account.handleAuthDeepLink(token: token)
                        AppDelegate.startRecorderIfWanted()
                    case .refresh:
                        await account.refresh()
                    }
                }
            }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 600)

        MenuBarExtra {
            MenuBarContent(appState: appState, recorder: recorder, account: account, flow: flow)
        } label: {
            MenuBarLabel(status: recorder.status)
                .task {
                    // Lives for the app's lifetime — the menu-bar label is created once at launch.
                    for await _ in NotificationCenter.default.notifications(named: .openFlowTimeline) {
                        openWindow(id: "main")
                        appState.selectedSection = .flow
                        flow.beginBrowsingTimeline()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Carries lifecycle callbacks SwiftUI's scene phase doesn't reliably surface.
/// `sharedRecorder` / `sharedFlowController` are set by their owners' `init()`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor static weak var sharedRecorder: RecorderController?
    @MainActor static weak var sharedFlowController: FlowController?
    @MainActor static weak var sharedHotkeys: HotkeyManager?
    @MainActor static weak var sharedAccount: AccountStore?
    @MainActor static weak var sharedSettings: SettingsStore?

    /// Starts the recorder iff the user is signed in and has `startRecordingOnLaunch`
    /// enabled. Safe to call multiple times — the recorder is idempotent.
    @MainActor static func startRecorderIfWanted() {
        guard let acct = sharedAccount, case .signedIn = acct.state else { return }
        guard sharedSettings?.startRecordingOnLaunch != false else { return }
        Task { await sharedRecorder?.start() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        AppDelegate.startRecorderIfWanted()

        // Global hotkeys: ⌃⌥R toggles a Flow recording; ⌃⌥G opens the "grab last N minutes" picker.
        AppDelegate.sharedHotkeys?.register(HotkeyManager.recordToggle) {
            Task { @MainActor in await AppDelegate.sharedFlowController?.toggleRecording() }
        }
        AppDelegate.sharedHotkeys?.register(HotkeyManager.grabLast) {
            NotificationCenter.default.post(name: .openFlowTimeline, object: nil)
        }

        // Local-notification permission for "skill ready for review" (best-effort).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }

        // Offer to finish an interrupted Flow recording, if one was left behind.
        if let flow = AppDelegate.sharedFlowController, let manifest = flow.checkForRecovery() {
            let a = NSAlert()
            a.messageText = "An earlier recording was interrupted"
            a.informativeText = "Mengo Flow found a recording you didn't finish (the app quit mid-recording). Synthesize a skill from it now?"
            a.addButton(withTitle: "Synthesize it")
            a.addButton(withTitle: "Discard")
            if a.runModal() == .alertFirstButtonReturn {
                Task { @MainActor in await flow.synthesizeRecovery(manifestURL: manifest) }
            } else {
                try? FileManager.default.removeItem(at: manifest.deletingLastPathComponent())
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppDelegate.sharedFlowController?.dumpRecoveryIfRecording()
            AppDelegate.sharedRecorder?.stop()
            Log.line("app terminating")
        }
    }

    @MainActor static func postFlowNotification(_ body: String) {
        let content = UNMutableNotificationContent()
        content.title = "Mengo Flow"
        content.body = body
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
