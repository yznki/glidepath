import XCTest
@testable import Glidepath

final class TendCLITests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Two open PRs as the search returns them: #1301 with a failed check, an unresolved thread and a requested
    /// reviewer; #1302 from a fork, with a pending status context and no author.
    private let searchFixture = """
    {"data":{"search":{"nodes":[
      {"number":1301,"title":"Add export","body":"Adds CSV export","url":"https://github.com/acme/api/pull/1301",
       "isDraft":false,"isCrossRepository":false,"headRefName":"feat/export","headRefOid":"aaa111",
       "baseRefName":"main","additions":40,"deletions":2,"mergeable":"MERGEABLE","mergeStateStatus":"BLOCKED",
       "reviewDecision":"REVIEW_REQUIRED","updatedAt":"2026-10-26T09:00:00Z","author":{"login":"yznki"},
       "labels":{"nodes":[{"name":"backend"}]},
       "reviewRequests":{"nodes":[{"requestedReviewer":{"login":"gadi"}}]},
       "reviews":{"nodes":[{"id":"R1","state":"COMMENTED","author":{"login":"gadi"}}]},
       "reviewThreads":{"nodes":[{"id":"T1","isResolved":false,"comments":{"nodes":[
         {"id":"C1","databaseId":77,"body":"nit","path":"a.swift","line":12,"author":{"login":"gadi"}}]}}]},
       "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
         {"__typename":"CheckRun","name":"Unit Tests","status":"COMPLETED","conclusion":"FAILURE",
          "detailsUrl":"https://github.com/acme/api/actions/runs/11/job/22"},
         {"__typename":"StatusContext","context":"ci/lint","state":"SUCCESS","targetUrl":null}]}}}}]}},
      {"number":1302,"title":"Fork fix","body":null,"url":"https://github.com/acme/api/pull/1302",
       "isDraft":true,"isCrossRepository":true,"headRefName":"fix","headRefOid":"bbb222",
       "baseRefName":"main","additions":1,"deletions":1,"mergeable":null,"mergeStateStatus":null,
       "reviewDecision":null,"updatedAt":null,"author":null,"labels":{"nodes":[]},
       "reviewRequests":{"nodes":[]},"reviews":{"nodes":[]},"reviewThreads":{"nodes":[]},
       "commits":{"nodes":[{"commit":{"statusCheckRollup":{"contexts":{"nodes":[
         {"__typename":"StatusContext","context":"build","state":"PENDING","targetUrl":null}]}}}}]}}
    ]}}}
    """

    func testParseSearchReadsChecksThreadsAndForks() throws {
        let prs = try Tender.parseSearch(Data(searchFixture.utf8))
        XCTAssertEqual(prs.map(\.n), [1301, 1302])

        let first = prs[0]
        XCTAssertEqual(first.ciStatus, .failed)
        XCTAssertEqual(first.failedChecks.map(\.name), ["Unit Tests"])
        XCTAssertEqual(first.checks[1].conclusion, "SUCCESS")
        XCTAssertEqual(CIEvidence.ids(first.checks[0].url)?.run, 11)
        XCTAssertEqual(CIEvidence.ids(first.checks[0].url)?.job, 22)
        XCTAssertEqual(first.requested, ["gadi"])
        XCTAssertEqual(first.labels, ["backend"])
        XCTAssertEqual(first.branch, "feat/export")
        XCTAssertEqual(first.head, "aaa111")
        XCTAssertEqual(first.threads.map(\.isResolved), [false])
        XCTAssertEqual(first.threads[0].comments[0].databaseId, 77)
        XCTAssertEqual(first.reviews.map(\.state), ["COMMENTED"])
        XCTAssertFalse(first.isFork)

        let second = prs[1]
        XCTAssertTrue(second.isFork)
        XCTAssertTrue(second.isDraft)
        XCTAssertEqual(second.author, "")
        XCTAssertEqual(second.body, "")
        XCTAssertEqual(second.ciStatus, .pending)
        XCTAssertNil(second.checks[0].conclusion)
    }

    func testTendPlistRunsTheCheckEveryFiveMinutes() {
        let plist = Launchd.tendPlist(binary: "/opt/homebrew/bin/glidepath", path: "/usr/bin:/bin",
                                      logFile: "/fake/home/Library/Logs/glidepath-tend.log")
        XCTAssertEqual(plist["Label"] as? String, "dev.glidepath.tend")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], ["/opt/homebrew/bin/glidepath", "tend"])
        XCTAssertEqual(plist["StartInterval"] as? Int, 300)
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, false)
        XCTAssertEqual((plist["EnvironmentVariables"] as? [String: String])?["PATH"], "/usr/bin:/bin")
        XCTAssertEqual(plist["StandardOutPath"] as? String, "/fake/home/Library/Logs/glidepath-tend.log")
        XCTAssertEqual(plist["StandardErrorPath"] as? String, "/fake/home/Library/Logs/glidepath-tend.log")
        XCTAssertNoThrow(try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
    }

    func testSessionFlagsFollowTheTendConfig() throws {
        var config = try Config.parse("schedule = [\"07:00\"]\n", home: "/fake/home")
        config.tend.advisor = .off
        let off = Tender.sessionArguments(prompt: "Tend round.", systemPrompt: "skill", scratch: "/fake/scratch",
                                          worktree: "/fake/wt", config: config)
        XCTAssertTrue(off.contains("stream-json"))
        XCTAssertEqual(value(after: "--output-format", in: off), "stream-json")
        XCTAssertEqual(value(after: "--max-budget-usd", in: off), "2")
        XCTAssertEqual(value(after: "--model", in: off), "sonnet")
        XCTAssertFalse(off.contains("--advisor"))
        // The settings are JSON, which escapes slashes, so the check decodes them first.
        let settings = try XCTUnwrap(value(after: "--settings", in: off))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(settings.utf8)) as? [String: Any])
        let sandbox = try XCTUnwrap(root["sandbox"] as? [String: Any])
        let network = try XCTUnwrap(sandbox["network"] as? [String: Any])
        XCTAssertEqual(network["allowedDomains"] as? [String], config.tend.registries)
        let filesystem = try XCTUnwrap(sandbox["filesystem"] as? [String: Any])
        XCTAssertEqual(filesystem["denyRead"] as? [String], [
            "~/.config/gh", "~/.ssh", "~/.git-credentials", "~/Library/Keychains", "~/.claude", "~/.npmrc", "~/.aws",
            "~/.netrc", "~/.docker", "~/.kube", "~/.gnupg", "~/.config/glidepath", "~/Library/Application Support",
        ])
        XCTAssertEqual(value(after: "--allowedTools", in: off)?.contains("Edit(//fake/wt/**)"), true)
        XCTAssertEqual(TendConfig().registries, ["registry.npmjs.org", "pypi.org", "files.pythonhosted.org"])

        // A separate Claude account's folder is denied too, written as the config gives it.
        config.claudeConfigDir = "/fake/alt"
        let alt = Tender.sessionArguments(prompt: "Tend round.", systemPrompt: "skill", scratch: "/fake/scratch",
                                          worktree: "/fake/wt", config: config)
        let altSettings = try XCTUnwrap(value(after: "--settings", in: alt))
        let altRoot = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(altSettings.utf8)) as? [String: Any])
        let altSandbox = try XCTUnwrap(altRoot["sandbox"] as? [String: Any])
        let altFilesystem = try XCTUnwrap(altSandbox["filesystem"] as? [String: Any])
        XCTAssertEqual((altFilesystem["denyRead"] as? [String])?.last, "/fake/alt")

        config.tend.advisor = .opus
        let on = Tender.sessionArguments(prompt: "Tend round.", systemPrompt: "skill", scratch: "/fake/scratch",
                                         worktree: "/fake/wt", config: config)
        XCTAssertEqual(value(after: "--advisor", in: on), "opus")
    }

    func testTendResultReadsCommitMessageKey() throws {
        let json = #"{"action":"fix","summary":"Missing import.","commit_message":"Import the CSV writer","ran":["npm test"]}"#
        let result = try JSONDecoder().decode(TendResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.action, "fix")
        XCTAssertEqual(result.commitMessage, "Import the CSV writer")
        XCTAssertEqual(result.ran, ["npm test"])
        XCTAssertNil(result.confidence)
    }

    func testCloneLockIsPerRepo() {
        let paths = Paths(home: "/fake/home", env: [:])
        XCTAssertEqual(paths.cloneLock("acme/api"), "/fake/home/.local/state/glidepath/clone-acme-api.lock")
    }

    func testTranscriptReadsTheClaudeConfigFolderWhenSet() {
        let paths = Paths(home: "/fake/home", env: [:])
        XCTAssertEqual(Transcript.projectDir(paths: paths, cwd: "/fake/home/dev/clone", claudeDir: "/fake/alt"),
                       "/fake/alt/projects/-fake-home-dev-clone")
    }

    func testTendRunTitlesAndDigest() {
        func tend(_ action: String, check: String? = nil) -> RunState {
            var run = RunState.new(id: "t", now: t0, kind: "tend", target: "pr:acme/api#12")
            run.tendAction = action
            run.tendCheck = check
            run.repos = [RepoState(slug: "acme/api", prs: [
                PRState(n: 12, author: "yznki", title: "Export", stage: .post, active: false, verdict: nil,
                        reason: "Added the missing import.", tokens: 900),
            ], error: nil)]
            run.finish(at: t0.addingTimeInterval(60), error: nil)
            return run
        }
        XCTAssertEqual(RunDigest.title(for: tend("fixed")), "Fixed CI on #12")
        XCTAssertEqual(RunDigest.title(for: tend("reran", check: "Unit Tests")), "Reran Unit Tests on #12")
        XCTAssertEqual(RunDigest.title(for: tend("held")), "Fix held on #12")
        XCTAssertEqual(RunDigest.title(for: tend("stuck")), "Stuck on #12")

        let digest = RunDigest(run: tend("fixed"), running: false)
        XCTAssertEqual(digest.lead, "Fixed CI on #12")
        XCTAssertEqual(digest.rest, "Added the missing import.")
        XCTAssertEqual(digest.ownRows.count, 1)
        XCTAssertTrue(digest.stopped.isEmpty)
        XCTAssertNil(digest.failed)
    }

    private func value(after flag: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }
}
