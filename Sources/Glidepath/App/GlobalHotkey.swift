import AppKit
import Carbon.HIToolbox

/// The ⌥⌘G shortcut that opens the menu bar popover from any app. Carbon's RegisterEventHotKey needs no
/// Accessibility permission. The config key `hotkey` says whether it is on; Settings turns it on and off.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    /// Called on the main actor when the shortcut is pressed.
    var onFire: (() -> Void)?
    /// Whether ⌥⌘G is registered right now. Settings reads it to say why the shortcut is not working.
    private(set) var registered = false

    private static let signature: OSType = 0x47_50_74_68 // "GPth"

    /// Registers the shortcut when the config says so. A config that does not parse counts as the default: on.
    func applyConfig(_ paths: Paths) {
        onFire = { PopoverToggle.toggle() }
        apply(on: (try? Config.load(paths))?.hotkey ?? true)
    }

    /// Makes the registration match `on`. Called at launch and on every config reload; registering again is a no-op.
    func apply(on: Bool) {
        if on { _ = register() } else { unregister() }
    }

    /// Registers ⌥⌘G. False when the system refuses it, usually because another app already uses it.
    @discardableResult
    func register() -> Bool {
        if ref != nil { registered = true; return true }
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let userData = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(GetApplicationEventTarget(), GlobalHotkey.callback, 1, &spec, userData, &handler)
        }
        let id = EventHotKeyID(signature: GlobalHotkey.signature, id: 1)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_G), UInt32(cmdKey | optionKey), id,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == noErr, let newRef else {
            registered = false
            return false
        }
        ref = newRef
        registered = true
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
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
        // The status item's button lives in the status bar window that SwiftUI's MenuBarExtra creates.
        let buttons = NSApp.windows
            .filter { String(describing: type(of: $0)).contains("StatusBar") }
            .compactMap { $0.contentView }
            .flatMap { descendants(of: $0) }
            .compactMap { $0 as? NSStatusBarButton }
        if let button = buttons.first {
            button.performClick(nil)
        } else {
            WindowRouter.shared.open(nil)
        }
    }

    private static func descendants(of view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { descendants(of: $0) }
    }
}
