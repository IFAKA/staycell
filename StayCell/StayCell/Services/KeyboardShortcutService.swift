import AppKit
import Carbon.HIToolbox
import os.log

/// Global keyboard shortcuts for mode switching.
/// Uses Carbon HotKey API (the only way to register system-wide shortcuts on macOS without accessibility permissions).
@MainActor
final class KeyboardShortcutService {
    private let logger = Logger(subsystem: AppConstants.bundleIdentifier, category: "shortcuts")
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handler: ((Mode) -> Void)?

    // Shortcuts: Ctrl+Opt+Cmd + D/S/P/O
    private static let shortcuts: [(mode: Mode, keyCode: UInt32, modifiers: UInt32)] = [
        (.deepWork, UInt32(kVK_ANSI_D), UInt32(cmdKey | optionKey | controlKey)),
        (.shallowWork, UInt32(kVK_ANSI_S), UInt32(cmdKey | optionKey | controlKey)),
        (.personalTime, UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey | controlKey)),
        (.offline, UInt32(kVK_ANSI_O), UInt32(cmdKey | optionKey | controlKey)),
    ]

    func register(handler: @escaping (Mode) -> Void) {
        self.handler = handler

        // Install Carbon event handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &eventSpec, refcon, nil)

        // Register each hotkey
        for (index, shortcut) in Self.shortcuts.enumerated() {
            let hotKeyID = EventHotKeyID(signature: OSType(0x464F4355), id: UInt32(index)) // "FOCU"
            var hotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
            if status == noErr, let ref = hotKeyRef {
                hotKeyRefs.append(ref)
                logger.info("Registered hotkey for \(shortcut.mode.rawValue)")
            } else {
                logger.warning("Failed to register hotkey for \(shortcut.mode.rawValue): \(status)")
            }
        }
    }

    func unregister() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
    }

    fileprivate func handleHotKey(id: UInt32) {
        guard id < Self.shortcuts.count else { return }
        let mode = Self.shortcuts[Int(id)].mode
        logger.info("Hotkey triggered: \(mode.rawValue)")
        handler?(mode)
    }
}

private func hotKeyCallback(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)

    let service = Unmanaged<KeyboardShortcutService>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in
        service.handleHotKey(id: hotKeyID.id)
    }
    return noErr
}
