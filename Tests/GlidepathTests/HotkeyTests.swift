import XCTest
import Carbon.HIToolbox
@testable import Glidepath

final class HotkeyTests: XCTestCase {
    func testParsesModifiersAndKey() {
        XCTAssertEqual(HotkeySpec.parse("⌥⌘G"), .optionCommandG)
        XCTAssertEqual(HotkeySpec.parse("⌥⌘g"), .optionCommandG, "letters may be lower case")
        XCTAssertEqual(HotkeySpec.parse("⌃⇧⌘3"),
                       HotkeySpec(keyCode: 0x14, modifiers: 0x1000 | 0x0200 | 0x0100))
    }

    func testKeyCodesMatchCarbon() {
        XCTAssertEqual(HotkeySpec.parse("⌘A")?.keyCode, UInt32(kVK_ANSI_A))
        XCTAssertEqual(HotkeySpec.parse("⌘G")?.keyCode, UInt32(kVK_ANSI_G))
        XCTAssertEqual(HotkeySpec.parse("⌘Z")?.keyCode, UInt32(kVK_ANSI_Z))
        XCTAssertEqual(HotkeySpec.parse("⌘Q")?.keyCode, UInt32(kVK_ANSI_Q))
        XCTAssertEqual(HotkeySpec.parse("⌘0")?.keyCode, UInt32(kVK_ANSI_0))
        XCTAssertEqual(HotkeySpec.parse("⌘9")?.keyCode, UInt32(kVK_ANSI_9))
        XCTAssertEqual(HotkeySpec.parse("⌘5")?.keyCode, UInt32(kVK_ANSI_5))
        XCTAssertEqual(HotkeySpec.optionCommandG.modifiers, UInt32(optionKey | cmdKey))
    }

    func testRejectsWhatIsNotAShortcut() {
        for text in ["", "G", "⌘", "⌘⌘G", "⌘GG", "⌘-", "⌘F1", "⌥⌘ß", "G⌘", "⌘ G", "⌘G⌘"] {
            XCTAssertNil(HotkeySpec.parse(text), text)
        }
    }

    func testNeedsCommandControlOrOption() {
        XCTAssertNil(HotkeySpec.parse("⇧G"), "Shift alone is not a shortcut")
        XCTAssertNil(HotkeySpec.parse("⇧⇧G"))
        XCTAssertNotNil(HotkeySpec.parse("⇧⌘G"), "Shift with Command is")
    }

    func testSettingMapsToSpec() {
        XCTAssertEqual(HotkeySpec.from(.on), .optionCommandG)
        XCTAssertNil(HotkeySpec.from(.off))
        XCTAssertEqual(HotkeySpec.from(.custom("⌃⌥G")), HotkeySpec.parse("⌃⌥G"))
        XCTAssertEqual(HotkeySpec.from(.custom("nonsense")), .optionCommandG, "a bad string falls back to the default")
    }
}
