import XCTest
@testable import Glidepath

final class StatusTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// Configured, scheduled, nothing running, the last check fine.
    private func base() -> Snapshot {
        var snap = Snapshot(jobInstalled: true, nextRun: t0.addingTimeInterval(3600))
        snap.repoCount = 2
        var run = RunState.new(id: "r", now: t0)
        run.finish(at: t0, error: nil)
        snap.run = run
        return snap
    }

    func testQuiet() {
        XCTAssertEqual(GlideState.derive(base(), needs: 0), .quiet(next: t0.addingTimeInterval(3600)))
        var snap = base()
        snap.nextRun = nil
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .quiet(next: nil))
    }

    func testNeeds() {
        XCTAssertEqual(GlideState.derive(base(), needs: 3), .needs(count: 3))
    }

    func testCheckingASweepCountsItsReviews() throws {
        var snap = base()
        var run = RunState.new(id: "s", now: t0)
        try run.setPR(repo: "lumen/web", n: 1, stage: .post, author: nil, title: nil, verdict: .approve, reason: nil)
        try run.setPR(repo: "lumen/web", n: 2, stage: .review, author: nil, title: nil, verdict: nil, reason: nil)
        try run.setPR(repo: "lumen/web", n: 3, stage: .gather, author: nil, title: nil, verdict: nil, reason: nil)
        snap.run = run
        snap.running = true
        let state = GlideState.derive(snap, needs: 2)
        XCTAssertEqual(state, .checking(CheckProgress(done: 1, total: 3, repo: "lumen/web")))
        if case .checking(let p) = state { XCTAssertEqual(p.fraction ?? 0, 1.0 / 3, accuracy: 0.001) }
    }

    func testCheckingWhileListingHasNoProgress() {
        var snap = base()
        snap.run = RunState.new(id: "s", now: t0)
        snap.running = true
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .checking(CheckProgress()))
        XCTAssertNil(CheckProgress().fraction)
    }

    func testCheckingADryRun() {
        var snap = base()
        snap.dryRunning = true
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .checking(CheckProgress()))
    }

    func testCheckingYourPRsOnlyWhileARoundWorks() {
        var snap = base()
        snap.tendRunning = true
        snap.approach = ApproachSnapshot(updated: t0, planes: [], needs: [], queued: 0)
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .quiet(next: snap.nextRun), "a check that only reads PRs is quiet")
        snap.approach?.working = "Fixing lint on #4"
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .checking(CheckProgress(yourPRs: true)))
    }

    func testPaused() {
        var snap = base()
        snap.paused = true
        snap.pausedUntil = t0.addingTimeInterval(7200)
        XCTAssertEqual(GlideState.derive(snap, needs: 2), .paused(until: t0.addingTimeInterval(7200)))
        snap.pausedUntil = nil
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .paused(until: nil))
    }

    func testEveryProblemNamesItsFix() {
        var snap = base()
        snap.repoCount = 0
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .problem(reason: .notSetUp, fix: .setUp))

        snap = base()
        snap.jobInstalled = false
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .problem(reason: .notScheduled, fix: .installSchedule))

        XCTAssertEqual(GlideState.derive(base(), needs: 0, jobError: "launchctl said no"),
                       .problem(reason: .scheduleFailed("launchctl said no"), fix: .installSchedule))

        snap = base()
        snap.run?.error = "gh: To get started with GitHub CLI, please run:  gh auth login"
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .problem(reason: .signedOut, fix: .signIn))

        snap.run?.error = "claude exited 1: boom"
        XCTAssertEqual(GlideState.derive(snap, needs: 4),
                       .problem(reason: .checkFailed("The review agent stopped early (exit 1)"), fix: .showLog),
                       "a broken check outranks what needs the user")
    }

    func testARunningCheckHidesTheLastFailure() {
        var snap = base()
        snap.run?.error = "boom"
        snap.dryRunning = true
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .checking(CheckProgress()))
    }

    func testHoldingBackForUsageOrQuietHours() {
        var snap = base()
        snap.tendOn = true
        let reset = t0.addingTimeInterval(1800)
        snap.queue = [TendQueueItem(slug: "a/b", n: 1, cls: .deferred, until: t0.addingTimeInterval(9000),
                                    reason: UsageGuard.quietReason)]
        XCTAssertEqual(GlideState.derive(snap, needs: 0),
                       .holdingBack(reason: .quietHours, resumesAt: t0.addingTimeInterval(9000)))
        snap.queue.append(TendQueueItem(slug: "a/b", n: 2, cls: .normal, until: reset, reason: "Paused for usage · resets 14:00"))
        snap.usage = UsageReading(used: 70, reserve: 30, resetsAt: reset)
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .holdingBack(reason: .usageReserve(reserve: 30), resumesAt: reset),
                       "the usage wait wins: it holds back urgent work too")
        XCTAssertEqual(GlideState.derive(snap, needs: 1), .needs(count: 1), "what needs the user comes first")
        snap.tendOn = false
        XCTAssertEqual(GlideState.derive(snap, needs: 0), .quiet(next: snap.nextRun), "a queue left from before tending was off")
    }

    func testUsageReadingTakesTheBusiestLiveWindow() {
        var usage = UsageState()
        usage.record([UsageWindow(type: "five_hour", utilization: 0.55, resetsAt: t0.addingTimeInterval(600), seen: t0),
                      UsageWindow(type: "seven_day", utilization: 0.81, resetsAt: t0.addingTimeInterval(86_400), seen: t0),
                      UsageWindow(type: "old", utilization: 0.99, resetsAt: t0.addingTimeInterval(-1), seen: t0)])
        let reading = usage.reading(reserve: 20, now: t0)
        XCTAssertEqual(reading, UsageReading(used: 81, reserve: 20, resetsAt: t0.addingTimeInterval(86_400)))
        XCTAssertTrue(reading?.overReserve ?? false)
        XCTAssertNil(UsageState().reading(reserve: 20, now: t0))
    }

    // MARK: Since you last looked

    func testSinceCountsWhatWentOutAfterTheLook() throws {
        let look = t0
        var before = RunState.new(id: "a", now: look.addingTimeInterval(-600))
        try before.setPR(repo: "x/y", n: 1, stage: .post, author: nil, title: nil, verdict: .approve, reason: nil)
        var after = RunState.new(id: "b", now: look.addingTimeInterval(600))
        try after.setPR(repo: "x/y", n: 2, stage: .post, author: nil, title: nil, verdict: .changes, reason: nil)
        try after.setPR(repo: "x/y", n: 3, stage: .post, author: nil, title: nil, verdict: .approve, reason: nil)
        try after.setPR(repo: "x/y", n: 4, stage: .post, author: nil, title: nil, verdict: .approve, reason: nil)
        try after.setPR(repo: "x/y", n: 5, stage: nil, author: nil, title: nil, verdict: .skipped, reason: "draft")
        after.repos[0].prs[1].draft = true            // held, not posted
        after.repos[0].prs[2].draft = false           // discarded
        // A draft from before the look that the user posted after it.
        before.repos[0].prs[0].draft = false
        before.repos[0].prs[0].posted = look.addingTimeInterval(60)
        var dry = RunState.new(id: "c", now: look.addingTimeInterval(700))
        try dry.setPR(repo: "x/y", n: 6, stage: .post, author: nil, title: nil, verdict: .approve, reason: nil)
        dry.dryRun = true
        var fixed = RunState.new(id: "d", now: look.addingTimeInterval(800), kind: "tend", target: "pr:x/y#7")
        fixed.repos = [RepoState(slug: "x/y", prs: [PRState(n: 7, stage: .post, active: false, tokens: 0)], error: nil)]
        fixed.tendAction = "fixed"
        var held = fixed
        held.id = "e"
        held.tendAction = "held"
        let landed = [TendLanded(slug: "x/y", n: 8, title: "", sha: "", parent: "", at: look.addingTimeInterval(900), status: "ok"),
                      TendLanded(slug: "x/y", n: 9, title: "", sha: "", parent: "", at: look.addingTimeInterval(-900), status: "ok")]

        let since = SinceLastLooked.make(runs: [after, dry, fixed, held, before], landed: landed, after: look)
        XCTAssertEqual(since, SinceLastLooked(reviewsPosted: 2, fixesPushed: [7], merged: [8]))
        XCTAssertEqual(Copy.since(since), "Posted 2 reviews, pushed a fix to #7, merged #8")
        XCTAssertTrue(SinceLastLooked.make(runs: [before], landed: [], after: look.addingTimeInterval(120)).isEmpty)
    }

    // MARK: Stop

    /// Starts `sleep`, in a process group of its own when `leader`, as `glidepath run` and `glidepath tend` put themselves.
    private func spawnSleep(leader: Bool = true) throws -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        if leader {
            posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETPGROUP))
            posix_spawnattr_setpgroup(&attr, 0)
        }
        var pid: pid_t = 0
        let argv: [UnsafeMutablePointer<CChar>?] = [strdup("/bin/sleep"), strdup("30"), nil]
        defer { argv.forEach { free($0) } }
        guard posix_spawn(&pid, "/bin/sleep", nil, &attr, argv, environ) == 0 else { throw StateError("spawn failed") }
        return pid
    }

    /// The signal that ended `pid`, or nil when it exited on its own.
    private func endSignal(_ pid: pid_t) -> Int32? {
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        let sig = status & 0x7f
        return sig == 0 ? nil : sig
    }

    private func kill9(_ pid: pid_t) {
        kill(pid, SIGKILL)
        _ = endSignal(pid)
    }

    private func tempPaths() throws -> Paths {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("gp-stop-\(UUID().uuidString)").path
        addTeardownBlock { try? FileManager.default.removeItem(atPath: home) }
        let paths = Paths(home: home, env: [:])
        try FileManager.default.createDirectory(atPath: paths.runsDir, withIntermediateDirectories: true)
        return paths
    }

    /// A test cannot start a binary named glidepath, so `sleep` stands in for one.
    private let anySleep: (pid_t) -> Bool = { _ in true }

    func testStopSignalsTheSweepAndTheTendRoundThenTidies() throws {
        let paths = try tempPaths()
        let sweepPid = try spawnSleep()
        let tendPid = try spawnSleep()
        var locks = [try XCTUnwrap(try RunLock.acquire(paths.lockFile)), try XCTUnwrap(try RunLock.acquire(paths.tendLockFile))]
        try "\(sweepPid)".write(toFile: paths.pidFile, atomically: true, encoding: .utf8)
        try "\(tendPid)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)
        try RunStore(paths: paths).save(RunState.new(id: "live", now: t0))
        let tend = TendStore(paths: paths)
        try tend.saveApproach(ApproachSnapshot(updated: t0, planes: [], needs: [], queued: 0, working: "Fixing lint on #4"))

        let signalled = Stop.signal(paths, isOurs: anySleep)
        XCTAssertEqual(signalled, Stop.Signalled(sweep: true, tend: true))
        XCTAssertEqual(endSignal(sweepPid), SIGTERM)
        XCTAssertEqual(endSignal(tendPid), SIGTERM)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.pidFile), "a signalled pid is never read again")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.tendPidFile))

        // Still held: settle waits, then says what still runs, and tidies nothing.
        XCTAssertEqual(Stop.settle(paths, signalled, run: "live", within: 0.2), signalled)
        XCTAssertNil(try RunStore(paths: paths).load("live").finished)
        XCTAssertNotNil(tend.loadApproach()?.working)

        locks.removeAll()
        XCTAssertEqual(Stop.settle(paths, signalled, run: "live", within: 0.2), Stop.Signalled())
        XCTAssertNotNil(try RunStore(paths: paths).load("live").finished, "a stopped run is recorded as finished")
        XCTAssertNil(tend.loadApproach()?.working, "the round's working line goes")
    }

    func testStopNeverSignalsAPidWhoseLockIsFree() throws {
        let paths = try tempPaths()
        let pid = try spawnSleep()
        defer { kill9(pid) }
        try "\(pid)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)

        XCTAssertFalse(Stop.signal(paths, isOurs: anySleep).any, "a pid left by a crash is not a running check")
        XCTAssertEqual(kill(pid, 0), 0, "the process was not signalled")
    }

    func testStopNeverSignalsAPidReusedByAnotherProgram() throws {
        let paths = try tempPaths()
        let lock = try XCTUnwrap(try RunLock.acquire(paths.tendLockFile))
        defer { withExtendedLifetime(lock) {} }
        // A stale pid the OS gave to another program: not a glidepath binary, whether or not it leads a group.
        for leader in [true, false] {
            let pid = try spawnSleep(leader: leader)
            defer { kill9(pid) }
            try "\(pid)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)
            XCTAssertFalse(Stop.isGlidepath(pid))
            XCTAssertFalse(Stop.signal(paths).any)
            XCTAssertEqual(kill(pid, 0), 0, "the process was not signalled")
        }
        // A pid that no longer exists.
        let gone = try spawnSleep()
        kill9(gone)
        try "\(gone)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)
        XCTAssertFalse(Stop.signal(paths, isOurs: anySleep).any)
    }

    func testStopNeverSignalsItselfOrItsOwnGroup() throws {
        let paths = try tempPaths()
        let lock = try XCTUnwrap(try RunLock.acquire(paths.tendLockFile))
        defer { withExtendedLifetime(lock) {} }
        for pid in [getpid(), 1, 0, -getpgrp()] {
            try "\(pid)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)
            XCTAssertFalse(Stop.signal(paths, isOurs: anySleep).any, "pid \(pid)")
        }
        // A process in this test's own group is signalled alone, never with the group.
        let member = try spawnSleep(leader: false)
        try "\(member)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)
        XCTAssertTrue(Stop.signal(paths, isOurs: anySleep).tend)
        XCTAssertEqual(endSignal(member), SIGTERM, "and this test is still running")
    }

    func testPauseMarksPausedAndStopsWhatRuns() throws {
        let paths = try tempPaths()
        let pid = try spawnSleep()
        var lock = try RunLock.acquire(paths.tendLockFile)
        XCTAssertNotNil(lock)
        try "\(pid)".write(toFile: paths.tendPidFile, atomically: true, encoding: .utf8)

        XCTAssertEqual(try Pause.pause(paths, isOurs: anySleep), Stop.Signalled(tend: true))
        XCTAssertTrue(Pause.isPaused(paths), "the marker is written first, so a check starting now skips itself")
        XCTAssertEqual(endSignal(pid), SIGTERM)
        lock = nil
        XCTAssertEqual(try Pause.pause(paths, isOurs: anySleep), Stop.Signalled(), "nothing left to stop")
    }

    func testIsHeldDoesNotMakeAStartingCheckSkip() throws {
        let paths = try tempPaths()
        let probe = open(paths.tendLockFile, O_CREAT | O_RDONLY, 0o644)
        XCTAssertEqual(flock(probe, LOCK_SH | LOCK_NB), 0)
        // An isHeld probe's brief hold, released 50 ms in.
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { flock(probe, LOCK_UN); close(probe) }
        XCTAssertNotNil(try RunLock.acquire(paths.tendLockFile))
    }
}
