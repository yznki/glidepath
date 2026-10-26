import XCTest
@testable import Glidepath

final class CopyTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    /// 2027-01-15 08:00 UTC, a Friday.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testEveryStatusHasASentenceAndOneButton() {
        let later = now.addingTimeInterval(3 * 3600)
        let clock = Copy.clock(later, calendar: calendar)
        let cases: [(GlideState, String, String)] = [
            (.quiet(next: later), "All good. Next check at \(clock).", "Check now"),
            (.quiet(next: nil), "All good.", "Check now"),
            (.checking(CheckProgress(done: 1, total: 3, repo: "lumen/web")), "Checking 3 PRs in lumen/web…", "Stop"),
            (.checking(CheckProgress(total: 1)), "Checking 1 PR…", "Stop"),
            (.checking(CheckProgress()), "Checking…", "Stop"),
            (.checking(CheckProgress(yourPRs: true)), "Working on your PRs…", "Stop"),
            (.needs(count: 1), "1 thing needs you.", "Open"),
            (.needs(count: 2), "2 things need you.", "Open"),
            (.paused(until: later), "Paused until \(clock).", "Resume"),
            (.paused(until: later.addingTimeInterval(86_400)), "Paused until tomorrow at \(clock).", "Resume"),
            (.paused(until: nil), "Paused.", "Resume"),
            (.problem(reason: .signedOut, fix: .signIn), "Can't reach GitHub: sign-in expired.", "Sign in"),
            (.problem(reason: .notSetUp, fix: .setUp), "Pick the repos to check.", "Set up"),
            (.problem(reason: .notScheduled, fix: .installSchedule), "Checks aren't scheduled.", "Fix"),
            (.problem(reason: .checkFailed("boom"), fix: .showLog), "Last check failed: boom.", "Show log"),
            (.holdingBack(reason: .usageReserve(reserve: 20), resumesAt: later),
             "Holding back: 20% of your usage is kept for you. Resumes at \(clock).", "Adjust"),
            (.holdingBack(reason: .quietHours, resumesAt: nil), "Waiting for quiet hours.", "Adjust"),
        ]
        for (state, sentence, button) in cases {
            XCTAssertEqual(Copy.status(state, now: now, calendar: calendar), sentence)
            XCTAssertEqual(Copy.statusButton(state), button)
        }
    }

    func testEveryNeedHasALabelAReasonAndANamedButton() {
        func need(_ kind: NeedKind, _ action: NeedAction, outward: Bool, reason: String = "") -> Need {
            Need(id: "x", kind: kind, repo: "a/b", number: 1, title: "t", author: nil, reason: reason, action: action,
                 outward: outward, since: nil)
        }
        let cases: [(Need, String, String, String?)] = [
            (need(.reviewReady(.changes), .post, outward: true), "Review ready to post", "Post review", "Hold to post"),
            (need(.fixReady, .push, outward: true, reason: "Fixed it"), "Fix ready to push", "Push fix", "Hold to push"),
            (need(.replyReady(to: "gadi"), .reply, outward: true, reason: "Why?"), "Reply ready", "Send reply", "Hold to send"),
            (need(.question(from: "noa"), .reply, outward: true), "Needs your answer", "Send reply", "Hold to send"),
            (need(.readyToMerge, .merge, outward: true), "Ready to merge", "Merge", "Hold to merge"),
            (need(.mainBroke(failing: ["lint"]), .revert, outward: true), "Revert ready", "Open revert PR", "Hold to open"),
            (need(.splitProposed(parts: 3), .reviewSplit, outward: false), "Split proposed", "Review split", nil),
            (need(.stuck, .retry, outward: false, reason: "It gave up"), "Stuck", "Try again", nil),
            (need(.waitingOnReviewer(login: "gadi", hours: 26), .ping, outward: true), "Waiting on gadi for 26 h", "Ping gadi",
             "Hold to ping"),
            (need(.tooLarge(lines: 12_480), .reviewAnyway, outward: false), "Skipped: too large", "Review anyway", nil),
        ]
        for (n, label, button, hint) in cases {
            XCTAssertEqual(Copy.label(n.kind), label)
            XCTAssertEqual(Copy.button(n), button)
            XCTAssertEqual(Copy.holdHint(n), hint)
            XCTAssertFalse(Copy.reason(n).isEmpty, label)
        }
        XCTAssertEqual(Copy.reason(need(.replyReady(to: "gadi"), .reply, outward: true, reason: "Why?")), "gadi: \u{201C}Why?\u{201D}")
        XCTAssertEqual(Copy.reason(need(.stuck, .retry, outward: false, reason: "It gave up")), "It gave up.")
    }

    // MARK: Cut words

    /// spec §3: words cut from the UI. "Try again" is the one allowed use of "try" (spec §4.3 names it); "draft" is only
    /// ever "draft PR".
    static let cut = ["approach", "plane", "marker", "gate", "runway", "tower", "lane", "in the air", "flight recorder",
                      "round", "try", "council", "sweep", "landed", "briefing", "playbook", "tend", "hands-off"]

    /// The files whose string literals must be clean. Phase 1 covers the new model and Copy; later phases add the UI.
    static let files = ["Core/NeedsYou.swift", "Core/Status.swift", "App/Copy.swift"]

    static func hits(in literal: String) -> [String] {
        let text = literal.replacingOccurrences(of: "Try again", with: "", options: .caseInsensitive)
        var found = cut.filter { word in
            text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: word))\\b",
                       options: [.regularExpression, .caseInsensitive]) != nil
        }
        if text.range(of: "\\bdrafts?\\b(?! PR)", options: [.regularExpression, .caseInsensitive]) != nil { found.append("draft") }
        return found
    }

    func testTheCutWordCheckCatches() {
        XCTAssertEqual(Self.hits(in: "Sweep done"), ["sweep"])
        XCTAssertEqual(Self.hits(in: "Fix held · try 1 of 2"), ["try"])
        XCTAssertEqual(Self.hits(in: "Post the draft"), ["draft"])
        XCTAssertEqual(Self.hits(in: "Mark ready, not a draft PR"), [])
        XCTAssertEqual(Self.hits(in: "Try again"), [])
        XCTAssertEqual(Self.hits(in: "Extend the rules, attend to it"), [])
    }

    func testNoCutWordsInNewFiles() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Glidepath")
        let literal = try NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
        for file in Self.files {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
                for match in literal.matches(in: line, range: NSRange(line.startIndex..., in: line)) {
                    guard let range = Range(match.range(at: 1), in: line) else { continue }
                    let hits = Self.hits(in: String(line[range]))
                    XCTAssertTrue(hits.isEmpty, "\(file):\(i + 1) uses \(hits) in \"\(line[range])\"")
                }
            }
        }
    }
}
