import SwiftUI

/// The "Whose PRs" choice on the review step.
private enum AuthorChoice: Hashable { case collaborators, anyone, people }

/// The "Days" choice on the schedule step. A custom week from an existing config is shown as a note instead.
private enum DaysChoice: Hashable { case weekdays, everyDay }

/// Steps 4 to 6 of the onboarding window: how to review, the schedule, and the first sweep with its landing.
extension OnboardingView {
    // MARK: 4. How to review

    var review: some View {
        let count = model.state.repos.count
        return VStack(alignment: .leading, spacing: 0) {
            heading("How to review")
            lead("These settings apply to the \(count) repo\(count == 1 ? "" : "s") you picked. Each repo can change later in Repos.")
                .padding(.top, WinMetrics.s8)
            VStack(alignment: .leading, spacing: 0) {
                reviewRow("How reviews post", "What lands on the pull request.") {
                    WinSegmented(
                        segments: [Posting.comment, .review, .draft].map {
                            WinSegmented<Posting>.Segment(value: $0, title: $0.modeLabel)
                        },
                        selected: model.state.posting
                    ) { model.state.posting = $0 }
                    Text(model.state.posting.preview)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.muted)
                        .padding(.horizontal, WinMetrics.s12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WinTheme.surface))
                }
                reviewRow("Whose PRs", "Your own PRs are never reviewed.") {
                    WinSegmented(
                        segments: [
                            WinSegmented<AuthorChoice>.Segment(value: .collaborators, title: "Collaborators"),
                            WinSegmented<AuthorChoice>.Segment(value: .anyone, title: "Anyone"),
                            WinSegmented<AuthorChoice>.Segment(value: .people, title: "These people…"),
                        ],
                        selected: authorChoice
                    ) { choice in
                        model.message = nil
                        switch choice {
                        case .collaborators: model.state.authors = .collaborators
                        case .anyone: model.state.authors = .anyone
                        case .people:
                            if case .logins = model.state.authors {} else { model.state.authors = .logins([]) }
                        }
                    }
                    if authorChoice == .people {
                        loginEditor
                    }
                }
                reviewRow("Review rules", "Optional.") {
                    Text("Add review rules later in Repos.")
                        .font(.system(size: 13))
                        .foregroundStyle(WinTheme.muted)
                }
            }
            .padding(.top, WinMetrics.s32)
            amberMessage(model.message)
            Spacer(minLength: 0)
            bar {
                WinButton(title: "Continue", style: .primary) { model.advance() }
                    .disabled(!model.state.canContinue(from: .review))
            }
        }
    }

    private var authorChoice: AuthorChoice {
        switch model.state.authors {
        case .collaborators: return .collaborators
        case .anyone: return .anyone
        case .logins: return .people
        }
    }

    /// The login chips with × and a field that adds a login on Enter. Continue waits for at least one login.
    private var loginEditor: some View {
        let logins: [String] = {
            if case .logins(let current) = model.state.authors { return current }
            return []
        }()
        return VStack(alignment: .leading, spacing: WinMetrics.s8) {
            if !logins.isEmpty {
                HStack(spacing: WinMetrics.s8) {
                    ForEach(logins, id: \.self) { login in
                        chip(login, mono: false) { model.removeLogin(login) }
                    }
                }
            }
            TextField(logins.isEmpty ? "Add a login, then Enter" : "login", text: $model.loginText)
                .winField()
                .frame(width: 220)
                .onSubmit { model.addLogin() }
        }
    }

    /// A row of the step: title, detail, then the control, with a rule above.
    private func reviewRow<Control: View>(_ title: String, _ detail: String,
                                          @ViewBuilder control: () -> Control) -> some View {
        VStack(alignment: .leading, spacing: WinMetrics.s8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WinTheme.text)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.faint)
            control()
        }
        .padding(.vertical, WinMetrics.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(WinTheme.line).frame(height: 1)
        }
    }

    // MARK: 5. Schedule

    var schedule: some View {
        VStack(alignment: .leading, spacing: 0) {
            heading("Schedule")
            lead("Sweeps run at these times on these days. Click the day to add a time, drag a pin to move it.")
                .padding(.top, WinMetrics.s8)
            DayStrip(
                times: model.state.schedule,
                onAdd: { minute in
                    model.editSchedule { try ScheduleEditor.addTime($0, hour: minute / 60, minute: minute % 60) }
                },
                onMove: { time, minute in
                    model.editSchedule { try ScheduleEditor.moveTime($0, from: time, hour: minute / 60, minute: minute % 60) }
                }
            )
            .padding(.top, WinMetrics.s32)
            HStack(spacing: WinMetrics.s8) {
                ForEach(model.state.schedule, id: \.self) { time in
                    chip(time.clock, mono: false) {
                        model.editSchedule { try ScheduleEditor.removeTime($0, time) }
                    }
                }
            }
            .padding(.top, WinMetrics.s16)
            daysRow
            amberMessage(model.message)
            Spacer(minLength: 0)
            bar {
                WinButton(title: "Continue", style: .primary) { model.advance() }
                    .disabled(!model.state.canContinue(from: .schedule))
            }
        }
    }

    @ViewBuilder
    private var daysRow: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s8) {
            Text("Days")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WinTheme.text)
            Text("Sweeps skip the other days.")
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.faint)
            if case .custom = model.state.days {
                Text("Custom days from your config. Change them in Schedule.")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
            } else {
                WinSegmented(
                    segments: [
                        .init(value: DaysChoice.weekdays, title: "Weekdays"),
                        .init(value: DaysChoice.everyDay, title: "Every day"),
                    ],
                    selected: model.state.days == .all ? .everyDay : .weekdays
                ) { choice in
                    model.state.days = choice == .everyDay ? .all : .weekdays
                }
            }
        }
        .padding(.top, WinMetrics.s32)
    }

    /// A time chip (base.css `.chip`): 28 tall, raised fill, a × that removes it.
    private func chip(_ text: String, mono: Bool, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(WinTheme.text)
                .monospacedDigit()
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WinTheme.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WinMetrics.s12)
        .frame(height: 28)
        .background(Capsule().fill(WinTheme.raised))
    }

    // MARK: 6. First sweep

    var firstSweep: some View {
        let first = model.state.repos.first ?? "your repo"
        let showsRun = model.state.firstSweep == .running || model.isLanded
        return VStack(alignment: .leading, spacing: 0) {
            heading(model.isLanded ? "You're set" : "First sweep")
            lead(sweepLead(first))
                .padding(.top, WinMetrics.s8)
            if let note = model.backupNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                    .padding(.top, WinMetrics.s8)
            }
            amberMessage(failureText)
            if showsRun {
                sweepField
                    .padding(.top, WinMetrics.s24)
                WinScroll {
                    VStack(spacing: 0) {
                        ForEach(Array(model.liveStrips.enumerated()), id: \.element.id) { index, strip in
                            sweepRow(strip, first: index == 0)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, WinMetrics.s8)
            } else {
                Spacer(minLength: 0)
            }
            sweepBar
        }
    }

    private var failureText: String? {
        if case .failed(let text) = model.state.firstSweep { return text }
        return nil
    }

    private func sweepLead(_ first: String) -> String {
        switch model.state.firstSweep {
        case .notRun:
            return "Glidepath dry-runs \(first): it reviews the open PRs and posts nothing. The schedule stays paused until you turn it on."
        case .running:
            return "Reviewing \(first) now. Nothing is posted."
        case .finished(_, let summary):
            return summary
        case .failed:
            return "The first sweep did not finish. Nothing is posted."
        }
    }

    /// The hero field with the glide dot while the dry run works; it rests at touchdown once the sweep has landed.
    private var sweepField: some View {
        let running = model.state.firstSweep == .running
        return TimelineView(.animation(paused: !running || reduceMotion)) { context in
            HeroField(t: running && !reduceMotion ? HeroField.glide(context.date) : 1)
        }
        .frame(height: 176)
    }

    /// One PR of the dry run: title over repo and number, and its verdict in the status column. A PR still in review
    /// shows its word in blue.
    private func sweepRow(_ strip: Strip, first: Bool) -> some View {
        HStack(spacing: WinMetrics.s16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(strip.title ?? "#\(strip.number)")
                    .font(.system(size: 14))
                    .foregroundStyle(WinTheme.text)
                    .lineLimit(1)
                Text("\(strip.repo) #\(strip.number)" + (strip.author.map { " · \($0)" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                    .lineLimit(1)
            }
            Spacer(minLength: WinMetrics.s8)
            if let kind = verdictKind(strip) {
                WinStatus(kind: kind)
            } else {
                Text("Reviewing")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WinTheme.blue)
                    .frame(width: 88, alignment: .trailing)
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(WinTheme.line).frame(height: 1) }
        }
    }

    private func verdictKind(_ strip: Strip) -> WinStatus.Kind? {
        switch strip.verdict {
        case .approve: return .approved
        case .changes: return .changes
        case .skipped: return strip.skipReason == "size" ? .tooLarge : .skipped
        case nil: return nil
        }
    }

    /// The footer for each phase: Run before the sweep, a disabled Running while it works, and the landing pair after.
    @ViewBuilder
    private var sweepBar: some View {
        switch model.state.firstSweep {
        case .notRun, .failed:
            bar {
                WinButton(title: failureText == nil ? "Run the first sweep" : "Try again", style: .primary) {
                    model.runFirstSweep()
                }
                .disabled(model.state.repos.isEmpty)
            }
        case .running:
            HStack {
                Spacer(minLength: 0)
                WinButton(title: "Running…", style: .primary) {}
                    .disabled(true)
            }
            .modifier(FooterFrame())
        case .finished:
            HStack(spacing: WinMetrics.s12) {
                Spacer(minLength: 0)
                WinButton(title: "Post nothing yet", style: .outline, large: true) { model.postNothingYet() }
                WinButton(title: "Turn on the schedule", style: .primary) { model.turnOnSchedule() }
            }
            .modifier(FooterFrame())
        }
    }
}

/// The landing line: what the dry run would post. Pure, so the wording can be checked without a run.
enum OnboardingSummary {
    static func landing(_ strips: [Strip], posting: Posting, repo: String) -> (reviews: Int, text: String) {
        let reviewed = strips.filter { $0.verdict == .approve || $0.verdict == .changes }
        let changes = reviewed.filter { $0.verdict == .changes }.count
        let approvals = reviewed.count - changes
        let skipped = strips.filter { $0.verdict == .skipped }.count
        let n = reviewed.count
        guard n > 0 else {
            return (0, "The dry run found no PRs to review in \(repo). Scheduled sweeps keep checking for new ones.")
        }
        if posting == .draft {
            return (n, "Would save \(n) \(n == 1 ? "draft" : "drafts") for you to post.")
        }
        var text = "Would post \(n) \(n == 1 ? "review" : "reviews") to \(repo) as \(posting.modeLabel.lowercased()): "
            + "\(changes) need changes, \(approvals) approve."
        if skipped > 0 { text += " \(skipped) too large to review on their own." }
        return (n, text)
    }
}

/// What the first sweep does, in order. Blocking: the caller runs it off the main thread. Each step is the one `glidepath
/// init` runs, so the app and the CLI leave the same files behind.
enum OnboardingSetup {
    static func run(config: Config, paths: Paths, env: [String: String]) throws -> ShellResult {
        let binary = InitCommand.binaryPath()
        // Paused before the job is written, so a sweep that starts before the user turns the schedule on skips itself.
        try Pause.set(true, paths)
        for repo in config.repos {
            do {
                try RepoClone.sync(repo, env: env)
            } catch {
                throw ConfigError(message: "\(repo.slug): \(error)")
            }
        }
        guard let skill = InitCommand.findInstalledDir(relative: "share/glidepath", fallback: "skill/glidepath",
                                                       requiredFile: "SKILL.md", from: binary) else {
            throw ConfigError(message: "skill files not found next to \(binary)")
        }
        try InitCommand.installSkill(from: skill, to: paths.skillDir)
        // As in init, a failed app link does not stop setup.
        if let app = InitCommand.findApp(from: binary) {
            try? InitCommand.linkApp(InstallKind.appTarget(binary: binary, app: app), at: paths.appLink)
        }
        try InitCommand.installJob(paths: paths, config: config, binary: binary,
                                   path: GitNexus.jobPath(base: env["PATH"] ?? "/usr/bin:/bin", home: paths.home))
        // The config is written last: if any step above fails, no config exists and onboarding opens again next launch.
        try ConfigEditor.save(config, paths: paths)
        return Shell.run(binary, ["run", "--dry-run", "--repo", config.repos[0].slug], env: env, timeout: 3600)
    }
}
