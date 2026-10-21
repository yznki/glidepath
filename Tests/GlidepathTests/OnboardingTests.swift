import XCTest
@testable import Glidepath

final class OnboardingTests: XCTestCase {
    private let allRequired = ToolStatus(claudeSignedIn: true, ghSignedIn: true, gitReady: true, gitNexus: false)

    private func state(tools: ToolStatus, repos: [String] = []) -> OnboardingState {
        var s = OnboardingState()
        s.tools = tools
        s.repos = repos
        return s
    }

    func testStepOrderIsTheRailOrder() {
        XCTAssertEqual(OnboardingStep.allCases.map(\.label),
                       ["Welcome", "Your tools", "Repos", "How to review", "Schedule", "First sweep"])
        XCTAssertEqual(OnboardingStep.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5])
    }

    func testToolsCannotContinueWithoutTheThreeRequired() {
        let missingClaude = ToolStatus(claudeSignedIn: false, ghSignedIn: true, gitReady: true, gitNexus: true)
        let missingGh = ToolStatus(claudeSignedIn: true, ghSignedIn: false, gitReady: true, gitNexus: true)
        let missingGit = ToolStatus(claudeSignedIn: true, ghSignedIn: true, gitReady: false, gitNexus: true)
        XCTAssertFalse(state(tools: ToolStatus()).canContinue(from: .tools))
        XCTAssertFalse(state(tools: missingClaude).canContinue(from: .tools))
        XCTAssertFalse(state(tools: missingGh).canContinue(from: .tools))
        XCTAssertFalse(state(tools: missingGit).canContinue(from: .tools))
        XCTAssertTrue(state(tools: allRequired).canContinue(from: .tools))
    }

    func testOptionalGitNexusDoesNotBlock() {
        XCTAssertFalse(allRequired.gitNexus)
        XCTAssertTrue(state(tools: allRequired).canContinue(from: .tools))
        XCTAssertTrue(ToolStatus(claudeSignedIn: true, ghSignedIn: true, gitReady: true, gitNexus: false).requiredMet)
    }

    func testBackFromWelcomeIsNil() {
        let s = OnboardingState()
        XCTAssertNil(s.back(from: .welcome))
        XCTAssertFalse(s.canGoBackFrom(.welcome))
        XCTAssertEqual(s.back(from: .tools), .welcome)
        XCTAssertTrue(s.canGoBackFrom(.firstSweep))
    }

    func testNextWalksTheStepsAndStopsAtTheLast() {
        let s = OnboardingState()
        var step: OnboardingStep? = .welcome
        var seen: [OnboardingStep] = []
        while let current = step {
            seen.append(current)
            step = s.next(from: current)
        }
        XCTAssertEqual(seen, OnboardingStep.allCases)
        XCTAssertNil(s.next(from: .firstSweep))
    }

    func testReposNeedAtLeastOneSelection() {
        XCTAssertFalse(state(tools: allRequired).canContinue(from: .repos))
        XCTAssertTrue(state(tools: allRequired, repos: ["acme/api"]).canContinue(from: .repos))
    }

    func testPeoplePolicyNeedsALogin() {
        var s = OnboardingState()
        s.authors = .logins([])
        XCTAssertFalse(s.canContinue(from: .review))
        s.authors = .logins(["octocat"])
        XCTAssertTrue(s.canContinue(from: .review))
    }

    func testFirstSweepCannotContinueUntilItFinishes() {
        var s = OnboardingState()
        s.firstSweep = .running
        XCTAssertFalse(s.canContinue(from: .firstSweep))
        s.firstSweep = .failed("boom")
        XCTAssertFalse(s.canContinue(from: .firstSweep))
        s.firstSweep = .finished(reviews: 2, summary: "Would post 2 reviews.")
        XCTAssertTrue(s.canContinue(from: .firstSweep))
    }

    func testConfigKeepsExistingReposAndAppliesChoicesToNewOnes() throws {
        let base = Config(schedule: [ScheduleTime("07:00")!], limits: Limits(), repos: [
            RepoConfig(slug: "acme/a", clone: "/clones/a", posting: .review),
            RepoConfig(slug: "acme/gone", clone: "/clones/gone"),
        ])
        var s = OnboardingState()
        s.repos = ["acme/b", "acme/a"]
        s.posting = .comment
        s.schedule = [ScheduleTime("09:00")!]
        s.days = .weekdays
        let config = s.config(base: base, home: "/home/me")
        XCTAssertEqual(config.repos.map(\.slug), ["acme/a", "acme/b"])
        XCTAssertEqual(config.repos[0].posting, .review, "a repo already in the config keeps its settings")
        XCTAssertEqual(config.repos[1].posting, .comment)
        XCTAssertEqual(config.repos[1].clone, "/home/me/glidepath/clones/acme-b")
        XCTAssertEqual(config.schedule, [ScheduleTime("09:00")!])
        XCTAssertEqual(config.days, .weekdays)
    }

    func testInitialSelectionComesFromTheExistingConfig() {
        let existing = Config(schedule: [ScheduleTime("08:00")!], limits: Limits(), repos: [
            RepoConfig(slug: "acme/a", clone: "/clones/a"),
        ])
        let s = OnboardingState.initial(existing: existing)
        XCTAssertEqual(s.repos, ["acme/a"])
        XCTAssertEqual(s.schedule, [ScheduleTime("08:00")!])
        XCTAssertEqual(OnboardingState.initial(existing: nil).repos, [])
    }

    func testRepoListParsingKeepsOnlyValidSlugs() throws {
        let json = """
        [{"nameWithOwner":"acme/old","primaryLanguage":null,"pushedAt":"2026-01-01T00:00:00Z"},
         {"nameWithOwner":"acme/new","primaryLanguage":{"name":"Go"},"pushedAt":"2026-10-20T12:00:00Z"},
         {"nameWithOwner":"not a slug","primaryLanguage":null,"pushedAt":null}]
        """
        let repos = RepoDiscovery.parseRepos(Data(json.utf8))
        XCTAssertEqual(repos.map(\.slug), ["acme/old", "acme/new"])
        XCTAssertEqual(repos[1].language, "Go")
        XCTAssertNil(repos[0].language)
    }

    func testOpenPRCountsGroupByRepository() {
        let json = """
        [{"repository":{"nameWithOwner":"acme/api"}},{"repository":{"nameWithOwner":"acme/api"}},
         {"repository":{"nameWithOwner":"acme/web"}}]
        """
        XCTAssertEqual(RepoDiscovery.parseOpenCounts(Data(json.utf8)), ["acme/api": 2, "acme/web": 1])
    }

    func testMergeDedupesSortsAndCapsOwnerLists() {
        func repo(_ slug: String, _ pushed: TimeInterval) -> DiscoveredRepo {
            DiscoveredRepo(slug: slug, language: nil, pushedAt: Date(timeIntervalSince1970: pushed), openPRs: nil)
        }
        let mine = [repo("me/old", 100), repo("me/new", 300)]
        let org = [repo("org/shared", 200), repo("me/new", 50), repo("org/tie", 300)]
        XCTAssertEqual(RepoDiscovery.merge([mine, org]).map(\.slug), ["me/new", "org/tie", "org/shared", "me/old"])
        XCTAssertEqual(RepoDiscovery.merge([mine, org], cap: 2).map(\.slug), ["me/new", "org/tie"])
    }

    func testLandingSummaryCountsVerdicts() {
        func strip(_ n: Int, _ verdict: Verdict?, skip: String? = nil) -> Strip {
            Strip(repo: "acme/api", number: n, author: nil, title: nil, reason: nil, stage: 4, active: false,
                  verdict: verdict, tokens: 0, skipReason: skip)
        }
        let strips = [strip(1, .changes), strip(2, .approve), strip(3, .skipped, skip: "size")]
        let summary = OnboardingSummary.landing(strips, posting: .comment, repo: "acme/api")
        XCTAssertEqual(summary.reviews, 2)
        XCTAssertEqual(summary.text, "Would post 2 reviews to acme/api as comment: 1 need changes, 1 approve. 1 too large to review on their own.")
        XCTAssertEqual(OnboardingSummary.landing([], posting: .draft, repo: "acme/api").reviews, 0)
    }

    /// Setup pauses a new job, and leaves an installed one as it is.
    func testSetupPausesOnlyWhenNoJobIsInstalled() {
        XCTAssertTrue(Pause.pausesOnSetup(jobInstalled: false))
        XCTAssertFalse(Pause.pausesOnSetup(jobInstalled: true))
    }

    /// "Post nothing yet" pauses only a job this setup created.
    func testPostNothingPausesOnlyACreatedJob() {
        XCTAssertTrue(Pause.pausesOnPostNothing(createdJob: true))
        XCTAssertFalse(Pause.pausesOnPostNothing(createdJob: false))
    }

    /// A reopened window lands on the first sweep only when a config exists and that sweep failed.
    func testResumeStepReopensOnFailedFirstSweepOnlyWithConfig() {
        XCTAssertEqual(OnboardingState.resumeStep(configExists: true, failedSweep: "boom"), .firstSweep)
        XCTAssertEqual(OnboardingState.resumeStep(configExists: false, failedSweep: "boom"), .welcome)
        XCTAssertEqual(OnboardingState.resumeStep(configExists: true, failedSweep: nil), .welcome)
        XCTAssertEqual(OnboardingState.resumeStep(configExists: false, failedSweep: nil), .welcome)
    }

    func testFailureTextOnlyForAFailedSweep() {
        XCTAssertEqual(OnboardingState.failure(of: .failed("boom")), "boom")
        XCTAssertNil(OnboardingState.failure(of: .notRun))
        XCTAssertNil(OnboardingState.failure(of: .running))
    }
}
