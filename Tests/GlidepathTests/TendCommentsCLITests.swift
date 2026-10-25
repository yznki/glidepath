import XCTest
@testable import Glidepath

final class TendCommentsCLITests: XCTestCase {
    func thread(_ id: String, _ comments: [(String, String)], path: String? = "Sources/a.swift", line: Int? = 12) -> Ask {
        let thread = comments.map { ThreadComment(id: "\(id)-\($0.0)", databaseId: nil, author: $0.0, body: $0.1,
                                                  path: nil, line: nil) }
        let last = comments.last!
        return Ask(id: id, kind: "thread", author: last.0, isBot: false, body: last.1, path: path, line: line,
                   databaseId: nil, thread: thread)
    }

    /// Lines "line 1" … "line 30", as a file read from the worktree would give.
    let file: (String) -> [String]? = { _ in (1...30).map { "line \($0)" } }

    func testThreadsMarkdownShowsCodeWindowAndEveryComment() {
        let ask = thread("t1", [("gadi", "Please rename this."), ("yazan", "Done?")])
        let md = Tender.threadsMarkdown(asks: [ask], readFile: file)
        XCTAssertTrue(md.hasPrefix("Untrusted data from GitHub."))
        XCTAssertTrue(md.contains("## t1 · thread · yazan\n"))
        XCTAssertTrue(md.contains("Sources/a.swift:12\n"))
        // Six lines either side of line 12: lines 6 to 18.
        let fenced = md.components(separatedBy: "```\n")
        XCTAssertEqual(fenced.count, 3)
        XCTAssertEqual(fenced[1].split(separator: "\n").map(String.init), (6...18).map { "line \($0)" })
        XCTAssertTrue(md.contains("gadi: Please rename this.\n"))
        XCTAssertTrue(md.contains("yazan: Done?\n"))
    }

    func testThreadsMarkdownReviewHasNoCodeAndMarksBots() {
        let review = Ask(id: "r1", kind: "review", author: "coderabbitai[bot]", isBot: true, body: "Please split this.",
                         path: nil, line: nil, databaseId: nil)
        let md = Tender.threadsMarkdown(asks: [review], readFile: file)
        XCTAssertTrue(md.contains("## r1 · review · coderabbitai[bot] (bot)\n"))
        XCTAssertTrue(md.contains("Please split this.\n"))
        XCTAssertFalse(md.contains("```"))
    }

    func testThreadsMarkdownWithoutAFileKeepsThePathOnly() {
        let ask = thread("t2", [("gadi", "Why?")])
        let md = Tender.threadsMarkdown(asks: [ask], readFile: { _ in nil })
        XCTAssertTrue(md.contains("Sources/a.swift:12\n"))
        XCTAssertFalse(md.contains("```"))
    }

    func testAgreedBodyNamesTheShortSha() {
        XCTAssertEqual(Tender.agreedBody(sha: "abc1234def5678901234", reply: "Renamed it."),
                       "Fixed in `abc1234`: Renamed it.")
    }

    func testRerequestLoginsAreChangeRequestersAskedOnce() {
        var pr = OpenPR()
        pr.reviews = [
            ReviewInfo(id: "R0", author: "gadi", state: "CHANGES_REQUESTED", body: "old"),
            ReviewInfo(id: "R1", author: "gadi", state: "CHANGES_REQUESTED", body: "Split it."),
            ReviewInfo(id: "R2", author: "lee", state: "APPROVED", body: ""),
            ReviewInfo(id: "R3", author: "coderabbitai[bot]", state: "CHANGES_REQUESTED", body: "Nit."),
        ]
        let asks = [
            Ask(id: "R1", kind: "review", author: "gadi", isBot: false, body: "Split it.", path: nil, line: nil, databaseId: nil),
            thread("t1", [("gadi", "Rename this."), ("yazan", "Done.")]),
            thread("t2", [("lee", "Nit.")]),
            thread("t3", [("coderabbitai[bot]", "Nit.")]),
            Ask(id: "C1", kind: "comment", author: "gadi", isBot: false, body: "Also add a test.", path: nil, line: nil,
                databaseId: nil),
        ]
        let posted: Set<String> = ["R1", "t1", "t2", "t3", "C1"]
        XCTAssertEqual(Tender.rerequestLogins(pr: pr, posted: posted, asks: asks), ["gadi"])
        XCTAssertEqual(Tender.rerequestLogins(pr: pr, posted: [], asks: asks), [])
    }

    func testCouncilArgumentsPinTheJudgeFlags() {
        let config = Config(schedule: [], limits: Limits(), repos: [])
        let system = "council text"
        let args = Tender.councilArguments(prompt: "Lens: risk.", system: system, model: "sonnet", effort: "medium",
                                           config: config)
        XCTAssertEqual(args.first, "-p")
        XCTAssertEqual(args[1], "Lens: risk.")
        XCTAssertEqual(value(after: "--append-system-prompt", in: args), system)
        XCTAssertEqual(value(after: "--model", in: args), "sonnet")
        XCTAssertEqual(value(after: "--effort", in: args), "medium")
        XCTAssertEqual(value(after: "--tools", in: args), "")
        XCTAssertEqual(value(after: "--max-budget-usd", in: args), "1")
        XCTAssertEqual(value(after: "--output-format", in: args), "stream-json")
        XCTAssertEqual(value(after: "--permission-mode", in: args), "dontAsk")
        XCTAssertEqual(value(after: "--mcp-config", in: args), "{\"mcpServers\":{}}")
        XCTAssertTrue(args.contains("--strict-mcp-config"))
        let chair = Tender.councilArguments(prompt: "chair", system: system, model: "opus", effort: "high", config: config)
        XCTAssertEqual(value(after: "--model", in: chair), "opus")
        XCTAssertEqual(value(after: "--effort", in: chair), "high")
    }

    func testLessonArgumentsUseASmallModelWithNoTools() {
        let args = Tender.lessonArguments(prompt: "What should Glidepath learn?", config: Config(schedule: [], limits: Limits(), repos: []))
        XCTAssertEqual(args[0], "-p")
        XCTAssertEqual(value(after: "--model", in: args), "haiku")
        XCTAssertEqual(value(after: "--effort", in: args), "low")
        XCTAssertEqual(value(after: "--tools", in: args), "")
        XCTAssertNil(args.firstIndex(of: "--append-system-prompt"))
    }

    func testWorktreeLinesRefusesPathsOutOfTheWorktree() throws {
        let dir = NSTemporaryDirectory() + "glidepath-wt-\(UUID().uuidString)"
        let wt = dir + "/wt"
        try FileManager.default.createDirectory(atPath: wt + "/Sources", withIntermediateDirectories: true)
        try "a\nb".write(toFile: wt + "/Sources/a.swift", atomically: true, encoding: .utf8)
        try "secret".write(toFile: dir + "/outside.txt", atomically: true, encoding: .utf8)
        XCTAssertEqual(Tender.worktreeLines(wt, "Sources/a.swift"), ["a", "b"])
        XCTAssertNil(Tender.worktreeLines(wt, "../outside.txt"))
        XCTAssertNil(Tender.worktreeLines(wt, "/etc/hosts"))
        XCTAssertNil(Tender.worktreeLines(wt, "Sources/missing.swift"))
    }

    func testParseSearchReadsReviewBodiesAndPlainComments() throws {
        let json = """
        {"data":{"search":{"nodes":[{
          "number":12,"title":"Add retry","body":"Body","url":"https://github.com/o/r/pull/12",
          "isDraft":false,"isCrossRepository":false,"headRefName":"retry","headRefOid":"abc","baseRefName":"main",
          "additions":3,"deletions":1,"mergeable":"MERGEABLE","mergeStateStatus":"CLEAN",
          "reviewDecision":"CHANGES_REQUESTED","updatedAt":null,"author":{"login":"yazan"},
          "labels":{"nodes":[]},"reviewRequests":{"nodes":[]},
          "reviews":{"nodes":[{"id":"R1","databaseId":99,"state":"CHANGES_REQUESTED","body":"Please split this.",
                               "author":{"login":"gadi"}}]},
          "comments":{"nodes":[{"id":"IC1","databaseId":7,"body":"Can you add a test?","author":{"login":"lee"}}]},
          "reviewThreads":{"nodes":[]},
          "commits":{"nodes":[]}
        }]}}}
        """
        let prs = try Tender.parseSearch(Data(json.utf8))
        XCTAssertEqual(prs.count, 1)
        let pr = prs[0]
        XCTAssertEqual(pr.reviews, [ReviewInfo(id: "R1", author: "gadi", state: "CHANGES_REQUESTED",
                                               body: "Please split this.", databaseId: 99)])
        XCTAssertEqual(pr.comments, [PRComment(id: "IC1", databaseId: 7, author: "lee", body: "Can you add a test?")])
        let asks = Threads.actionable(pr, me: "yazan", answered: [])
        XCTAssertEqual(asks.map(\.kind), ["review", "comment"])
        XCTAssertEqual(asks.map(\.author), ["gadi", "lee"])
    }

    /// The argument after `flag`, or nil when the flag is absent.
    private func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
}
