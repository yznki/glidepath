import XCTest
@testable import ReviewRadar

final class BashGuardTests: XCTestCase {
    func testAllowsPlainSubcommands() {
        XCTAssertNil(BashGuard.denial(for: "review-radar post --repo a/b --pr 1"))
        XCTAssertNil(BashGuard.denial(for: "review-radar pr threads --repo a/b --pr 12"))
        XCTAssertNil(BashGuard.denial(for: "review-radar state set --run r1 --repo a/b --pr 1 --stage review"))
        XCTAssertNil(BashGuard.denial(for: "review-radar code grep --pattern foo"))
        XCTAssertNil(BashGuard.denial(for: "review-radar code grep --pattern 'foo('"))
        XCTAssertNil(BashGuard.denial(for: "review-radar code grep --pattern '--force'"))
        XCTAssertNil(BashGuard.denial(for: "review-radar pr info --repo a/b --pr 3 --out pr.json"))
    }

    func testDeniesZshExpansionPayloads() {
        // Both run code under zsh -c if they get past the guard.
        XCTAssertNotNil(BashGuard.denial(for: "review-radar code grep --pattern =(touch x)"))
        XCTAssertNotNil(BashGuard.denial(for: "review-radar code grep --pattern /etc/host*(e:'touch x':)"))
    }

    func testDeniesCommandCompositionAndExpansion() {
        for command in [
            "review-radar x && (cat y)",
            "review-radar x <(cat y)",
            "review-radar x;y",
            "review-radar x | y",
            "review-radar x `id`",
            "review-radar x $(id)",
            "review-radar x {a,b}",
            "review-radar x ~/x",
            "review-radar x *",
            "review-radar x !",
            "review-radar x #",
            "review-radar x \\",
            "review-radar x > y",
            "review-radar x < y",
            "review-radar x & y",
            "review-radar x (y)",
            "review-radar x=1",
            "review-radar x'a'b",
            "review-radar x 'a'b",
            "review-radar x \"a\"",
            "review-radar x\tcat",
            "review-radar x\ncat y",
        ] {
            XCTAssertNotNil(BashGuard.denial(for: command), command)
        }
    }

    func testUnquotedDashValuesAreDenied() {
        XCTAssertNotNil(BashGuard.denial(for: "review-radar code grep --pattern --force"))
        XCTAssertNil(BashGuard.denial(for: "review-radar code grep --pattern '--force'"))
    }

    func testRequiresTheExactPrefix() {
        XCTAssertNotNil(BashGuard.denial(for: "review-radarx post"))
        XCTAssertNotNil(BashGuard.denial(for: " review-radar post"))
        XCTAssertNotNil(BashGuard.denial(for: "/usr/bin/review-radar post"))
        XCTAssertNotNil(BashGuard.denial(for: ""))
    }

    func testHookInputDecisions() {
        func input(_ tool: String, _ command: String?) -> Data {
            var obj: [String: Any] = ["tool_name": tool]
            if let command { obj["tool_input"] = ["command": command] }
            return try! JSONSerialization.data(withJSONObject: obj)
        }
        XCTAssertEqual(BashGuard.evaluate(stdin: input("Bash", "review-radar post --repo a/b --pr 1")).code, 0)
        let denied = BashGuard.evaluate(stdin: input("Bash", "ps aux"))
        XCTAssertEqual(denied.code, 2)
        XCTAssertTrue(denied.message?.contains("review-radar guard denied") ?? false)
        XCTAssertEqual(BashGuard.evaluate(stdin: input("Bash", nil)).code, 2)
        XCTAssertEqual(BashGuard.evaluate(stdin: Data("not json".utf8)).code, 2)
        XCTAssertEqual(BashGuard.evaluate(stdin: Data()).code, 2)
    }

    func testHookSettingsUseExecFormWithArgs() throws {
        let json = try JSONSerialization.jsonObject(with: Data(Claude.hookSettingsJSON(binary: "/opt/rr/bin/review-radar").utf8)) as? [String: Any]
        let pre = ((json?["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])?.first
        XCTAssertEqual(pre?["matcher"] as? String, "Bash")
        let hook = (pre?["hooks"] as? [[String: Any]])?.first
        XCTAssertEqual(hook?["command"] as? String, "/opt/rr/bin/review-radar")
        XCTAssertEqual(hook?["args"] as? [String], ["hook", "bash-guard"])
    }
}
