import Foundation

/// A global shortcut as Carbon registers it: a virtual key code and Carbon modifier bits. Pure, so the config
/// parser and tests can use it without Carbon.
struct HotkeySpec: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    /// ⌥⌘G, the shortcut `hotkey = true` means.
    static let optionCommandG = HotkeySpec(keyCode: 0x05, modifiers: cmd | option)

    // Carbon's modifier bits (cmdKey, shiftKey, optionKey, controlKey).
    private static let cmd: UInt32 = 0x0100
    private static let shift: UInt32 = 0x0200
    private static let option: UInt32 = 0x0800
    private static let control: UInt32 = 0x1000

    private static let glyphs: [Character: UInt32] = ["⌃": control, "⌥": option, "⇧": shift, "⌘": cmd]

    /// Key codes for A-Z and 0-9 on the ANSI layout (kVK_ANSI_*).
    private static let keys: [Character: UInt32] = [
        "A": 0x00, "S": 0x01, "D": 0x02, "F": 0x03, "H": 0x04, "G": 0x05, "Z": 0x06, "X": 0x07, "C": 0x08, "V": 0x09,
        "B": 0x0B, "Q": 0x0C, "W": 0x0D, "E": 0x0E, "R": 0x0F, "Y": 0x10, "T": 0x11, "O": 0x1F, "U": 0x20, "I": 0x22,
        "P": 0x23, "L": 0x25, "J": 0x26, "K": 0x28, "N": 0x2D, "M": 0x2E,
        "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15, "6": 0x16, "5": 0x17, "9": 0x19, "7": 0x1A, "8": 0x1C, "0": 0x1D,
    ]

    /// One or more of ⌃ ⌥ ⇧ ⌘ (each once), at least one of ⌃ ⌥ ⌘, then one key from A-Z or 0-9. Letters may be
    /// lower case. Nil for anything else, including a key with no modifier or only ⇧.
    static func parse(_ text: String) -> HotkeySpec? {
        var modifiers: UInt32 = 0
        var key: UInt32?
        let characters = Array(text)
        for (i, c) in characters.enumerated() {
            if let bit = glyphs[c] {
                guard modifiers & bit == 0 else { return nil }
                modifiers |= bit
            } else if i == characters.count - 1, let code = keyCode(c) {
                key = code
            } else {
                return nil
            }
        }
        guard modifiers & (cmd | option | control) != 0, let key else { return nil }
        return HotkeySpec(keyCode: key, modifiers: modifiers)
    }

    /// The key code for one letter or digit. Upper-casing can make two characters (ß), which is no key.
    private static func keyCode(_ c: Character) -> UInt32? {
        let upper = c.uppercased()
        return upper.count == 1 ? keys[Character(upper)] : nil
    }

    /// The spec a `hotkey` setting registers. Off has none; a custom string that does not parse falls back to ⌥⌘G.
    static func from(_ setting: HotkeySetting) -> HotkeySpec? {
        switch setting {
        case .off: return nil
        case .on: return optionCommandG
        case .custom(let text): return parse(text) ?? optionCommandG
        }
    }
}
