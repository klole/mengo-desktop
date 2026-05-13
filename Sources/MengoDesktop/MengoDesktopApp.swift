import SwiftUI
import AppKit
import UserNotifications

@main
@MainActor
struct MengoDesktopApp: App {
    @State private var appState = AppState()
    @State private var recorder: RecorderController
    @State private var hud: RecordingHUDController
    @State private var hotkeys: HotkeyManager
    @State private var flow: FlowController
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        Log.bootstrap()
        let rec = RecorderController()
        let h = RecordingHUDController()
        let hk = HotkeyManager()
        let fl = FlowController.live(recorder: rec, hud: h, notify: { AppDelegate.postFlowNotification($0) })
        _recorder = State(initialValue: rec)
        _hud = State(initialValue: h)
        _hotkeys = State(initialValue: hk)
        _flow = State(initialValue: fl)
        AppDelegate.sharedHotkeys = hk
    }

    var body: some Scene {
        Window("Mengo Desktop", id: "main") {
            MainWindowView(appState: appState, recorder: recorder, flow: flow)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 880, height: 600)

        MenuBarExtra {
            MenuBarContent(appState: appState, recorder: recorder, flow: flow)
        } label: {
            MenuBarLabel(status: recorder.status)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Task { await AppDelegate.sharedRecorder?.start() }

        // Global hotkey: ⌃⌥R toggles a Flow recording.
        AppDelegate.sharedHotkeys?.register(HotkeyManager.recordToggle) {
            Task { @MainActor in await AppDelegate.sharedFlowController?.toggleRecording() }
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
