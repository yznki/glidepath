import SwiftUI

/// The "Whose PRs" choice on the review step.
private enum AuthorChoice: Hashable { case collaborators, anyone, people }

/// Steps 4 to 6 of the onboarding window: how to review, the schedule, and the first sweep with its landing.
extension OnboardingView {
    // MARK: 4. How to review

    var review: some View {
        let count = model.state.repos.count
        return stepLayout(body: {
            VStack(alignment: .leading, spacing: 0) {
                heading("How to review")
                lead("These settings apply to the \(count) repo\(count == 1 ? "" : "s") you picked. Each repo can change later in Repos.")
                    .padding(.top, WinMetrics.s8)
                VStack(alignment: .leading, spacing: 0) {
                    reviewRow("How reviews post", "What lands on the pull request.") {
                        SettingSegmented(
                            options: [Posting.comment, .review, .draft].map { (value: $0, label: $0.modeLabel) },
                            selected: model.state.posting
                        ) { model.state.posting = $0 }
                        Text(model.state.posting.preview)
                            .font(.system(size: 12))
                            .foregroundStyle(Gotham.mute)
                            .padding(.horizontal, WinMetrics.s12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Gotham.row))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Gotham.edge, lineWidth: 1))
                    }
                    reviewRow("Whose PRs", "Your own PRs are never reviewed.") {
                        SettingSegmented(
                            options: [
                                (value: AuthorChoice.collaborators, label: "Collaborators"),
                                (value: AuthorChoice.anyone, label: "Anyone"),
                                (value: AuthorChoice.people, label: "These people…"),
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
                            .foregroundStyle(Gotham.mute)
                    }
                }
                .padding(.top, WinMetrics.s32)
                amberMessage(model.message)
            }
        }, footer: {
            bar {
                OnbButton(title: "Continue", style: .primary) { model.advance() }
                    .disabled(!model.state.canContinue(from: .review))
            }
        })
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
                .foregroundStyle(Gotham.fg)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
            control()
        }
        .padding(.vertical, WinMetrics.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Gotham.edge).frame(height: 1)
        }
    }

    // MARK: 5. Schedule

    var schedule: some View {
        stepLayout(body: {
            VStack(alignment: .leading, spacing: 0) {
                heading("Schedule")
                lead("Drag the ends to set the window, scroll the centre to set how often.")
                    .padding(.top, WinMetrics.s8)
                ScheduleDialView(dial: model.dial, reduced: Motion.reduced(reduceMotion), signal: Gotham.signal(signalKey))
                    .padding(.top, WinMetrics.s16)
                // The presets are left out here: beside the dial they need more width than the pane has.
                VStack(alignment: .leading, spacing: 8) {
                    Text("Days").cap()
                    DayPills(dial: model.dial, reduced: Motion.reduced(reduceMotion))
                }
                .padding(.top, 12)
                amberMessage(model.message)
            }
        }, footer: {
            bar {
                OnbButton(title: "Continue", style: .primary) { model.advance() }
                    .disabled(!model.state.canContinue(from: .schedule))
            }
        })
    }

    /// A time chip (base.css `.chip`): 28 tall, raised fill, a × that removes it.
    private func chip(_ text: String, mono: Bool, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(Gotham.fg)
                .monospacedDigit()
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Gotham.mute)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WinMetrics.s12)
        .frame(height: 28)
        .background(Capsule().fill(Gotham.tint))
        .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
    }

    // MARK: 6. First sweep

    var firstSweep: some View {
        let first = model.state.repos.first ?? "your repo"
        let showsRun = model.state.firstSweep == .running || model.isLanded
        let reviewing = model.liveStrips.filter { $0.verdict != .skipped }
        // The result list scrolls inside its own frame, so the body is not wrapped in another scroll view.
        return stepLayout(scrolls: false, body: {
            VStack(alignment: .leading, spacing: 0) {
                heading(model.isLanded ? "You're set" : "First sweep")
                lead(sweepLead(first, reviewing: reviewing))
                    .padding(.top, WinMetrics.s8)
                if model.state.firstSweep == .running {
                    Text(OnboardingSummary.progress(reviewing))
                        .font(.system(size: 12))
                        .foregroundStyle(Gotham.mute)
                        .padding(.top, WinMetrics.s4)
                }
                if let note = model.backupNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Gotham.mute)
                        .padding(.top, WinMetrics.s8)
                }
                amberMessage(failureText)
                if showsRun {
                    sweepField
                        .padding(.top, WinMetrics.s24)
                    let rows = reviewing.map { Presentation.row($0, running: true) }
                    WinScroll {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                sweepRow(row, first: index == 0)
                            }
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, WinMetrics.s8)
                    if let skipped = OnboardingSummary.skippedLine(model.liveStrips) {
                        Text(skipped)
                            .font(.system(size: 12))
                            .foregroundStyle(Gotham.mute)
                            .lineLimit(1)
                            .padding(.top, WinMetrics.s8)
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
        }, footer: {
            sweepBar
        })
    }

    private var failureText: String? {
        if case .failed(let text) = model.state.firstSweep { return text }
        return nil
    }

    private func sweepLead(_ first: String, reviewing: [Strip]) -> String {
        switch model.state.firstSweep {
        case .notRun:
            return "Glidepath dry-runs \(first): it reviews the open PRs and posts nothing. \(model.scheduleCopy)"
        case .running:
            return "Reviewing \(OnboardingSummary.reviewCount(reviewing)) to show what Glidepath would post. About 3 minutes."
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

    /// One PR being reviewed. In flight: the stage meter and its word. Landed: the verdict mark, with the reason in
    /// the signal colour when there is one, as Overview's Last sweep rows show it.
    private func sweepRow(_ row: RowModel, first: Bool) -> some View {
        let strip = row.strip
        let place = "\(strip.repo) #\(strip.number)" + (strip.author.map { " · \($0)" } ?? "")
        return HStack(spacing: WinMetrics.s16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(strip.title ?? "#\(strip.number)")
                    .font(.system(size: 14))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    if let reason = strip.reason, strip.verdict != nil {
                        Text(reason).foregroundStyle(Gotham.signal(signalKey))
                        Text(" · \(place)").foregroundStyle(Gotham.mute)
                    } else {
                        Text(place).foregroundStyle(Gotham.mute)
                    }
                }
                .font(.system(size: 12))
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if strip.verdict != nil {
                sweepVerdict(row)
            } else {
                HStack(spacing: WinMetrics.s16) {
                    sweepMeter(row.meter ?? [])
                    Text(RunRowViews.phaseWord(row))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Gotham.fg)
                        .frame(width: 88, alignment: .trailing)
                }
            }
        }
        .frame(height: 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(Gotham.edge).frame(height: 1) }
        }
    }

    /// The landed verdict in the 88 pt status column, in the Gotham colours: near-white for approve, the signal colour
    /// for changes, and a mute dash for skipped. The same mark as `RunRowViews.verdict`, which still has the old colours.
    @ViewBuilder
    private func sweepVerdict(_ row: RowModel) -> some View {
        HStack(spacing: WinMetrics.s8) {
            switch row.status {
            case .changes:
                Text("Changes").foregroundStyle(Gotham.signal(signalKey))
                StatusTriangle().fill(Gotham.signal(signalKey)).frame(width: 8, height: 7)
            case .approved:
                Text("Approved").foregroundStyle(Gotham.approve)
                Circle().fill(Gotham.approve).frame(width: 7, height: 7)
            case .skipped:
                Text("Skipped").foregroundStyle(Gotham.mute)
                Rectangle().fill(Gotham.mute).frame(width: 8, height: 2)
            default:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 88, alignment: .trailing)
    }

    /// Four 12 x 4 dashes: done in mute, the current stage in fg, the rest in edge.
    private func sweepMeter(_ segments: [MeterSegment]) -> some View {
        HStack(spacing: WinMetrics.s4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(segment == .done ? Gotham.mute : segment == .current ? Gotham.fg : Gotham.edge)
                    .frame(width: 12, height: 4)
            }
        }
    }

    /// The footer for each phase. Before the run: Run. While it runs and after it lands, the pair never blocks:
    /// Post nothing yet and Turn on the schedule both open Overview, and the dry run keeps going.
    @ViewBuilder
    private var sweepBar: some View {
        switch model.state.firstSweep {
        case .notRun, .failed:
            bar {
                OnbButton(title: failureText == nil ? "Run the first sweep" : "Try again", style: .primary) {
                    model.runFirstSweep()
                }
                .disabled(model.state.repos.isEmpty)
            }
        case .running, .finished:
            HStack(spacing: WinMetrics.s12) {
                Spacer(minLength: 0)
                OnbButton(title: "Post nothing yet", style: .outline, large: true) { model.postNothingYet() }
                OnbButton(title: "Turn on the schedule", style: .primary) { model.turnOnSchedule() }
            }
            .modifier(FooterFrame())
        }
    }
}

/// The landing line: what the dry run would post. Pure, so the wording can be checked without a run.
enum OnboardingSummary {
    /// The PR count in the running line: the PRs being reviewed, or "up to 3" before the run has listed them.
    static func reviewCount(_ reviewing: [Strip]) -> String {
        let n = reviewing.count
        guard n > 0 else { return "up to \(OnboardingSetup.dryRunPRs) PRs" }
        return "\(n) PR\(n == 1 ? "" : "s")"
    }

    /// "1 of 3 landed", against the PRs being reviewed.
    static func progress(_ reviewing: [Strip]) -> String {
        let landed = reviewing.filter { $0.verdict != nil }.count
        let total = reviewing.isEmpty ? OnboardingSetup.dryRunPRs : reviewing.count
        return "\(landed) of \(total) landed"
    }

    /// "7 skipped: 1 yours, 3 too large, 3 already reviewed", counted by reason. Nil when nothing was skipped.
    static func skippedLine(_ strips: [Strip]) -> String? {
        let skipped = strips.filter { $0.verdict == .skipped }
        guard !skipped.isEmpty else { return nil }
        var counts: [String: Int] = [:]
        for strip in skipped { counts[skipCategory(strip), default: 0] += 1 }
        let order = ["yours", "draft", "too large", "already reviewed", "bots", "past the limit", "other"]
        let parts = order.compactMap { label in counts[label].map { "\($0) \(label)" } }
        return "\(skipped.count) skipped: " + parts.joined(separator: ", ")
    }

    static func skipCategory(_ strip: Strip) -> String {
        let reason = strip.reason ?? ""
        if reason == "your own PR" { return "yours" }
        if reason.hasPrefix("draft") { return "draft" }
        if strip.skipReason == "size" || reason.hasPrefix("too large") { return "too large" }
        if reason.hasPrefix("already reviewed") { return "already reviewed" }
        if reason == "bot author" { return "bots" }
        if reason.hasPrefix("next sweep") || reason.hasPrefix("over max_prs_per_run") { return "past the limit" }
        return "other"
    }

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
    /// The first sweep reviews at most this many eligible PRs.
    static let dryRunPRs = 3

    static func run(config: Config, paths: Paths, env: [String: String]) throws -> ShellResult {
        let binary = InitCommand.stableBinary(runningBinary: InitCommand.binaryPath())
        // Paused before the job is written, so a sweep that starts before the user turns the schedule on skips itself.
        if Pause.pausesOnSetup(jobInstalled: FileManager.default.fileExists(atPath: paths.plistFile)) {
            try Pause.set(true, paths)
        }
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
        return Shell.run(binary, ["run", "--dry-run", "--repo", config.repos[0].slug, "--max-prs", "\(OnboardingSetup.dryRunPRs)"],
                         env: env, timeout: 3600)
    }
}
