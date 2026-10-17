import AppKit
import Carbon.HIToolbox

/// System-wide ⌥⌘K for Quick Access, via Carbon `RegisterEventHotKey` (no Accessibility permission needed).
/// Adapted from Dinky's GlobalHotkeyManager. Customizable shortcuts come later.
nonisolated final class GlobalHotkey: @unchecked Sendable {
    static let shared = GlobalHotkey()

    private static let signature: OSType = "SLNK".utf8.reduce(0) { ($0 << 8) + OSType($1) }
    private var hotKeyRef: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var onPress: (@MainActor () -> Void)?

    private init() {}

    @MainActor
    func registerQuickAccess(_ action: @escaping @MainActor () -> Void) {
        onPress = action
        unregister()
        installHandler()
        var id = EventHotKeyID()
        id.signature = Self.signature
        id.id = 1
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(optionKey | cmdKey), id,
                                         GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr { hotKeyRef = nil }
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), Self.callback, 1, &spec, nil, &handler)
    }

    private func fire() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onPress?() }
        }
    }

    private static let callback: EventHandlerUPP = { _, event, _ -> OSStatus in
        guard let event else { return OSStatus(eventNotHandledErr) }
        var id = EventHotKeyID()
        let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
        guard err == noErr, id.signature == GlobalHotkey.signature else { return OSStatus(eventNotHandledErr) }
        GlobalHotkey.shared.fire()
        return noErr
    }
}
