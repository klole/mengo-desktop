import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's `RegisterEventHotKey` to install process-wide global hotkeys.
/// Ported from V1's `ScreenpipeFlow/HotkeyManager`. macOS may prompt for an
/// Accessibility grant on first registration.
@MainActor
final class HotkeyManager {
    struct Binding {
        let keyCode: UInt32       // Carbon virtual key (e.g. kVK_ANSI_R == 15)
        let modifiers: UInt32     // Carbon mask (cmdKey, optionKey, controlKey, shiftKey)
    }

    static let recordToggle = Binding(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey))
    static let grabLast     = Binding(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey))

    private var registered: [(EventHotKeyRef, () -> Void)] = []
    private var eventHandlerRef: EventHandlerRef?

    init() { installHandler() }

    // No deinit: Carbon hotkey registrations / event handlers are process-bound;
    // the OS reclaims them on exit. (Cleanup here would cross actor isolation in
    // deinit, which Swift 6 forbids.)

    func register(_ binding: Binding, action: @escaping () -> Void) {
        var hkRef: EventHotKeyRef?
        let hkID = EventHotKeyID(signature: OSType(0x4D454E47),   // "MENG"
                                 id: UInt32(registered.count + 1))
        let status = RegisterEventHotKey(binding.keyCode, binding.modifiers, hkID,
                                         GetApplicationEventTarget(), 0, &hkRef)
        if status != noErr { Log.line("hotkey registration failed: status=\(status)"); return }
        if let ref = hkRef { registered.append((ref, action)) }
    }

    private func installHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                var hkID = EventHotKeyID()
                let status = GetEventParameter(eventRef, EventParamName(kEventParamDirectObject),
                                               EventParamType(typeEventHotKeyID), nil,
                                               MemoryLayout<EventHotKeyID>.size, nil, &hkID)
                guard status == noErr else { return status }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let idx = Int(hkID.id) - 1
                if idx >= 0, idx < manager.registered.count {
                    let action = manager.registered[idx].1
                    DispatchQueue.main.async { action() }
                }
                return noErr
            }, 1, &eventType, selfPtr, &eventHandlerRef)
    }
}
