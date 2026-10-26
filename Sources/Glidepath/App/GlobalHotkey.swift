import AppKit
import Carbon.HIToolbox

/// The ⌥⌘G shortcut that opens the menu bar popover from any app. Carbon's RegisterEventHotKey needs no
/// Accessibility permission. The config key `hotkey` says whether it is on; Settings turns it on and off.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// The shortcut `ref` holds, so a different one can replace it.
    private var shortcut: HotkeySpec?
    /// Called on the main actor when the shortcut is pressed.
    var onFire: (() -> Void)?
    /// Whether ⌥⌘G is registered right now. Settings reads it to say why the shortcut is not working.
    private(set) var registered = false

    private static let signature: OSType = 0x47_50_74_68 // "GPth"

    /// Registers the shortcut when the config says so. A config that does not parse counts as the default: on.
    func applyConfig(_ paths: Paths) {
        onFire = { PopoverToggle.toggle() }
        apply((try? Config.load(paths))?.hotkey ?? .on)
    }

    /// Makes the registration match `setting`. Called at launch and on every config reload; registering the same
    /// shortcut again is a no-op.
    func apply(_ setting: HotkeySetting) {
        guard let spec = HotkeySpec.from(setting) else { unregister(); return }
        _ = register(spec)
    }

    /// Registers `spec` (⌥⌘G by default). False when the system refuses it, usually because another app already uses it.
    @discardableResult
    func register(_ spec: HotkeySpec = .optionCommandG) -> Bool {
        if ref != nil, spec == shortcut { registered = true; return true }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let userData = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), GlobalHotkey.callback, 1, &spec, userData, &handler)
        }
        let id = EventHotKeyID(signature: GlobalHotkey.signature, id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(spec.keyCode, spec.modifiers, id, GetApplicationEventTarget(), 0, &newRef)
        // The old shortcut stays registered until the new one succeeds, so a refused shortcut leaves the old one working.
        guard status == noErr, let newRef else {
            registered = ref != nil
            return false
        }
        if let ref { UnregisterEventHotKey(ref) }
        ref = newRef
        shortcut = spec
        registered = true
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        shortcut = nil
        registered = false
    }

    private static let callback: EventHandlerUPP = { _, _, userData in
        guard let userData else { return noErr }
        let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
        DispatchQueue.main.async { MainActor.assumeIsolated { hotkey.onFire?() } }
        return noErr
    }
}

/// Opens and closes the menu bar popover the way a click on its status item does.
@MainActor
enum PopoverToggle {
    static func toggle() {
        if let menuBar = MenuBar.shared { menuBar.toggle() } else { WindowRouter.shared.open(nil) }
    }
}
