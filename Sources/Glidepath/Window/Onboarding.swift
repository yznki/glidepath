import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The onboarding window (v1.2 mockups onb-welcome, onb-tools, onb-repos): no sidebar, a 400 pt rail that draws the
/// glide slope with one point per step, and a pane with the step's title, leads and actions. Steps 4 to 6 are in
/// OnboardingFinish.swift. Shown while `WindowRouter.showOnboarding` is set.
struct OnboardingView: View {
    @ObservedObject var store: Store
    @StateObject var model: OnboardingModel
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// `model` is nil in the app; snapshot rendering passes a fixture model.
    init(store: Store, model: OnboardingModel? = nil) {
        self.store = store
        _model = StateObject(wrappedValue: model ?? OnboardingModel(paths: store.paths))
    }

    var body: some View {
        HStack(spacing: 0) {
            OnboardingRail(step: model.state.step, landed: model.isLanded)
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WinTheme.ground)
        .onChange(of: model.state.step) { _, step in
            // The steps that read the machine run their work when they open, off the main thread.
            if step == .tools { model.checkTools() }
            if step == .repos, model.repoList == .idle || model.repoList.failedMessage != nil { model.loadRepos() }
        }
    }

    /// The pane: the step's body, then the footer bar pinned to the bottom. Title row at 136, 64 side insets. The body
    /// is 520 wide; the footer bar takes the pane's full width inside the 64 insets (`FooterBar`), so it reads the
    /// pane width from the environment this sets.
    private var pane: some View {
        GeometryReader { geo in
            // The step gets exactly the height between the title zone and the bottom inset, so its footer lands on the
            // bottom edge whatever the body measures.
            VStack(alignment: .leading, spacing: WinMetrics.s24) {
                stepBody
                    .frame(maxWidth: 520, alignment: .topLeading)
                    .frame(height: max(0, geo.size.height - 136 - WinMetrics.canvasBottom), alignment: .topLeading)
            }
            .padding(.top, 136)
            .padding(.horizontal, 64)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .environment(\.paneWidth, geo.size.width)
        }
    }

    @ViewBuilder
    private var stepBody: some View {
        switch model.state.step {
        case .welcome: welcome
        case .tools: tools
        case .repos: repos
        case .review: review
        case .schedule: schedule
        case .firstSweep: firstSweep
        }
    }

    // MARK: Pieces shared by the steps

    /// A display title: 32/40 bold, tracking -0.6.
    func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 32, weight: .bold))
            .tracking(-0.6)
            .lineSpacing(2)
            .foregroundStyle(WinTheme.text)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A lead: 15/24 muted.
    func lead(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15))
            .lineSpacing(6)
            .foregroundStyle(WinTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The amber message under the lead: a config that failed validation, or a setup failure.
    @ViewBuilder
    func amberMessage(_ text: String?) -> some View {
        if let text {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.amberInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, WinMetrics.s12)
        }
    }

    /// The footer bar (44 tall): Back on the left when the step allows it, then the step's actions on the right.
    func bar<Trailing: View>(@ViewBuilder trailing: () -> Trailing) -> some View {
        FooterBar(back: model.state.canGoBackFrom(model.state.step) ? { model.goBack() } : nil, trailing: trailing())
    }

    /// A step's layout: the body fills the pane between the title area and the footer, and scrolls inside that space
    /// (`scrolls`), so a short window never pushes the footer off screen. A body that scrolls itself, such as a list,
    /// passes `scrolls: false`. The footer stays pinned at the bottom.
    func stepLayout<Body: View, Footer: View>(scrolls: Bool = true, @ViewBuilder body: () -> Body,
                                              @ViewBuilder footer: () -> Footer) -> some View {
        // The footer is 44 tall and sits on the bottom edge. The body stops 24 above it and is clipped, so overflow
        // scrolls or is cut inside the body and never moves the footer.
        let content = body()
            .frame(maxWidth: .infinity, maxHeight: scrolls ? nil : .infinity, alignment: .topLeading)
            .padding(.bottom, 44 + WinMetrics.s24)
        return ZStack(alignment: .bottom) {
            if scrolls {
                WinScroll { content }
            } else {
                content
            }
            footer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    // MARK: 1. Welcome

    private var welcome: some View {
        stepLayout(body: {
            VStack(alignment: .leading, spacing: 0) {
                GlidepathMark(size: 120, n: 11)
                heading("PRs reviewed\nbefore you're back.")
                    .padding(.top, WinMetrics.s32)
                lead("Glidepath runs Claude Code reviews of your team's pull requests on a schedule, checks every finding against the code, and posts one review per PR.")
                    .padding(.top, WinMetrics.s8)
                lead("Setup takes about three minutes. Nothing is posted until you say so.")
                    .padding(.top, WinMetrics.s12)
                amberMessage(model.message)
            }
        }, footer: {
            HStack(spacing: WinMetrics.s12) {
                WinButton(title: "Use my config file", style: .quiet) { model.useConfigFile() }
                Spacer(minLength: 0)
                WinButton(title: "Get started", style: .primary) { model.advance() }
            }
            .modifier(FooterFrame())
        })
    }

    // MARK: 2. Your tools

    private var tools: some View {
        stepLayout(body: {
            VStack(alignment: .leading, spacing: 0) {
                heading("Your tools")
                lead(toolsLead)
                    .padding(.top, WinMetrics.s8)
                VStack(spacing: 0) {
                    ForEach(Array(model.toolRows.enumerated()), id: \.element.id) { index, row in
                        toolRow(row, first: index == 0)
                    }
                }
                .padding(.top, WinMetrics.s32)
                if model.toolRows.isEmpty {
                    Text("Checking your tools…")
                        .font(.system(size: 13))
                        .foregroundStyle(WinTheme.faint)
                        .padding(.top, WinMetrics.s32)
                }
            }
        }, footer: {
            bar {
                WinButton(title: "Check again", style: .outline) { model.checkTools() }
                    .disabled(model.checkingTools)
                WinButton(title: "Continue", style: .primary) { model.advance() }
                    .disabled(!model.state.canContinue(from: .tools))
            }
        })
    }

    /// The lead names what is missing only when it is: GitNexus is optional, the required three block Continue.
    private var toolsLead: String {
        let base = "Glidepath drives tools you already use."
        if !model.state.tools.requiredMet && !model.toolRows.isEmpty {
            return base + " Fix the missing ones to continue."
        }
        return model.state.tools.gitNexus ? base + " All set." : base + " One is optional and missing."
    }

    /// One check: a 20 pt icon (green check or amber !), the title, its meta, and the fix command when it is missing.
    private func toolRow(_ row: ToolRow, first: Bool) -> some View {
        HStack(alignment: .top, spacing: WinMetrics.s16) {
            Text(row.ok ? "✓" : "!")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(row.ok ? WinTheme.green : WinTheme.amber)
                .frame(width: 20, height: 20)
                .background(Circle().fill(row.ok ? WinTheme.greenBg : WinTheme.amberBg))
            VStack(alignment: .leading, spacing: 0) {
                Text(row.title)
                    .font(.system(size: 14))
                    .foregroundStyle(WinTheme.text)
                Text(row.meta)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                    .padding(.top, 2)
                if !row.ok, let fix = row.fix {
                    fixBox(fix).padding(.top, WinMetrics.s12)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, first ? 0 : WinMetrics.s16)
        .padding(.bottom, WinMetrics.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            if !first { Rectangle().fill(WinTheme.line).frame(height: 1) }
        }
    }

    /// The fix command in a mono box with a Copy button (48 tall, surface fill).
    private func fixBox(_ command: String) -> some View {
        HStack(spacing: WinMetrics.s12) {
            Text(command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WinTheme.text)
                .lineLimit(1)
                .truncationMode(.middle)
            WinButton(title: model.copied == command ? "Copied" : "Copy", style: .outline) { model.copy(command) }
        }
        .padding(.leading, WinMetrics.s12)
        .padding(.trailing, WinMetrics.s8)
        .frame(height: 48)
        .background(RoundedRectangle(cornerRadius: 10).fill(WinTheme.surface))
    }

    // MARK: 3. Repos

    private var repos: some View {
        // The repo list scrolls inside its own frame, so the body does not wrap it in another scroll view.
        stepLayout(scrolls: false, body: {
            VStack(alignment: .leading, spacing: 0) {
                heading("Which repos?")
                lead("From your GitHub account and orgs. You can add more later.")
                    .padding(.top, WinMetrics.s8)
                TextField(model.repoList == .loaded ? "Search \(model.allRows.count) repos" : "Search repos", text: $model.search)
                    .winField()
                    .padding(.top, WinMetrics.s32)
                repoList
                    .padding(.top, WinMetrics.s8)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }, footer: {
            bar {
                Text("\(model.state.repos.count) selected")
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                WinButton(title: "Continue", style: .primary) { model.advance() }
                    .disabled(!model.state.canContinue(from: .repos))
            }
        })
    }

    @ViewBuilder
    private var repoList: some View {
        switch model.repoList {
        case .idle, .loading:
            Text("Loading your repos from GitHub…")
                .font(.system(size: 13))
                .foregroundStyle(WinTheme.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let text):
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.amberInk)
                .fixedSize(horizontal: false, vertical: true)
        case .loaded:
            let rows = model.filteredRows
            if rows.isEmpty {
                Text("No repos match \"\(model.search)\".")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.faint)
            } else {
                WinScroll {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.slug) { index, repo in
                            repoRow(repo, first: index == 0)
                        }
                    }
                }
            }
        }
    }

    /// A 56 pt row: checkbox, slug over language and last push, and the open PR count. Its rule sits inside the row.
    private func repoRow(_ repo: DiscoveredRepo, first: Bool) -> some View {
        let on = model.state.repos.contains(repo.slug)
        return Button {
            model.toggleRepo(repo.slug)
        } label: {
            HStack(spacing: WinMetrics.s16) {
                RepoCheckbox(on: on)
                VStack(alignment: .leading, spacing: 0) {
                    Text(repo.slug)
                        .font(.system(size: 14))
                        .foregroundStyle(WinTheme.text)
                        .lineLimit(1)
                    Text(model.meta(for: repo))
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: WinMetrics.s8)
                if let open = repo.openPRs {
                    Text("\(open) open PR\(open == 1 ? "" : "s")")
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.muted)
                        .monospacedDigit()
                }
            }
            .frame(height: 56)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) {
                if !first { Rectangle().fill(WinTheme.line).frame(height: 1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// The 18 pt checkbox (radius 5, 1.5 pt control stroke). Checked: text fill with a black check.
struct RepoCheckbox: View {
    let on: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(on ? WinTheme.text : Color.clear)
            RoundedRectangle(cornerRadius: 5).strokeBorder(on ? WinTheme.text : WinTheme.control, lineWidth: 1.5)
            if on {
                CheckShape()
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: 18, height: 18)
    }
}

/// The check mark inside an 18 pt box.
struct CheckShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.28, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.44, y: rect.height * 0.68))
        path.addLine(to: CGPoint(x: rect.width * 0.74, y: rect.height * 0.34))
        return path
    }
}

/// The rail (onb.css `.path`, kit.js approach()): the glide slope from (48,148) to (248,628), one point per step, done
/// points ink, the current point an amber dot with a soft halo, and the runway under the last step. Labels sit at x+20.
/// The done trail and the dot move with an ease-out when the step changes; both settle on the runway at landing.
struct OnboardingRail: View {
    let step: OnboardingStep
    let landed: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let start = CGPoint(x: 48, y: 148)
    static let end = CGPoint(x: 248, y: 628)
    static let last = OnboardingStep.allCases.count - 1
    /// Where the dot rests at landing: the middle of the runway.
    static let runwayRest = CGPoint(x: 300, y: 647.5)
    static let amber = Color(hex: "FFB020")

    static func point(_ index: Int) -> CGPoint {
        let t = CGFloat(index) / CGFloat(last)
        return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
    }

    var body: some View {
        let cur = step.rawValue
        let dot = landed ? OnboardingRail.runwayRest : OnboardingRail.point(cur)
        let trail: CGFloat = landed ? 1 : CGFloat(cur) / CGFloat(OnboardingRail.last)
        // The rail's points are fixed at the 720 pt design, but they sit in an overlay on a frame that takes the window's
        // height, so a shorter window clips the rail instead of growing the whole window.
        Color.clear
            .frame(width: 400)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .topLeading) {
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: OnboardingRail.start)
                p.addLine(to: OnboardingRail.end)
            }
            .stroke(WinTheme.track, lineWidth: 2)
            GlideTrail(fraction: trail)
                .stroke(WinTheme.text, lineWidth: 2)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(cur == OnboardingRail.last || landed ? WinTheme.text : WinTheme.track)
                .frame(width: 120, height: 3)
                .offset(x: 240, y: 646)
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                if item.rawValue != cur {
                    let p = OnboardingRail.point(item.rawValue)
                    Circle()
                        .fill(item.rawValue < cur ? WinTheme.text : WinTheme.track)
                        .frame(width: 8, height: 8)
                        .offset(x: p.x - 4, y: p.y - 4)
                }
            }
            Circle()
                .fill(OnboardingRail.amber.opacity(0.16))
                .frame(width: 28, height: 28)
                .offset(x: dot.x - 14, y: dot.y - 14)
            Circle()
                .fill(OnboardingRail.amber)
                .frame(width: 14, height: 14)
                .offset(x: dot.x - 7, y: dot.y - 7)
            ForEach(OnboardingStep.allCases, id: \.self) { item in
                let p = OnboardingRail.point(item.rawValue)
                Text(item.label)
                    .font(.system(size: 13, weight: item.rawValue == cur ? .semibold : .regular))
                    .foregroundStyle(item.rawValue == cur ? WinTheme.text : item.rawValue < cur ? WinTheme.muted : WinTheme.faint)
                    .lineLimit(1)
                    .frame(height: 18, alignment: .leading)
                    .offset(x: p.x + 20, y: p.y - 9)
            }
            HStack(spacing: 10) {
                GlidepathMark(size: 22, n: 7)
                Text("Glidepath")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WinTheme.text)
            }
            // The rail's 20 pt inset plus the brand row's 12 pt: the mark sits at 32, as onb.css's .obrand + .brand.
            .padding(.horizontal, WinMetrics.s12)
            .frame(height: 32)
            .offset(x: 20, y: 52)
        }
        .frame(width: 400, height: 720, alignment: .topLeading)
            }
            .clipped()
            .background(WinTheme.rail)
        .overlay(alignment: .trailing) {
            Rectangle().fill(WinTheme.line).frame(width: 1)
        }
        .clipped()
        .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: cur * 2 + (landed ? 1 : 0))
    }
}

/// The done part of the rail: from the first point to the point `fraction` of the way along the slope. Animatable, so
/// the trail grows with the step rather than jumping.
struct GlideTrail: Shape, Animatable {
    var fraction: CGFloat

    var animatableData: CGFloat {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let t = fraction
        path.move(to: OnboardingRail.start)
        path.addLine(to: CGPoint(x: OnboardingRail.start.x + (OnboardingRail.end.x - OnboardingRail.start.x) * t,
                                 y: OnboardingRail.start.y + (OnboardingRail.end.y - OnboardingRail.start.y) * t))
        return path
    }
}

extension View {
    /// A text field in the window's style (base.css `.field`): 32 tall, surface fill, control stroke, radius 8.
    func winField() -> some View {
        self
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundStyle(WinTheme.text)
            .padding(.horizontal, WinMetrics.s12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(WinTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WinTheme.control, lineWidth: 1))
    }
}

/// One check on the tools step. `fix` is the command shown with Copy while the row is not ok.
struct ToolRow: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let meta: String
    let ok: Bool
    let fix: String?
}

/// The repo list's load state.
enum RepoListState: Equatable {
    case idle, loading, loaded, failed(String)

    var failedMessage: String? {
        if case .failed(let text) = self { return text }
        return nil
    }
}

/// Runs the tool checks off the main thread. Pure reads: nothing is installed or changed here.
enum OnboardingChecks {
    struct Report: Sendable {
        let rows: [ToolRow]
        let status: ToolStatus
    }

    static func run(env: [String: String], home: String) -> Report {
        let items = Checks.tools(env: env)
        func passes(_ name: String) -> Bool { items.first { $0.name == name }?.ok ?? false }

        let claudeFound = passes("claude (Claude Code)")
        let claudeVersion = words(stdout("claude", ["--version"], env)).first ?? ""
        let claudeIn = claudeFound && claudeSignedIn(env)

        let ghFound = passes("gh (GitHub CLI)")
        let ghIn = passes("gh signed in")
        let login = ghIn ? stdout("gh", ["api", "user", "--jq", ".login"], env) : ""
        let ghVersion = words(stdout("gh", ["--version"], env)).dropFirst(2).first ?? ""

        // git is only run once the Command Line Tools are present: the /usr/bin shim opens an install prompt without them.
        let clt = passes("Xcode Command Line Tools")
        let gitReady = clt && passes("git")
        let gitVersion = gitReady ? (words(stdout("git", ["--version"], env)).dropFirst(2).first ?? "") : ""
        let nexus = GitNexus.find(path: env["PATH"], home: home) != nil

        let rows = [
            ToolRow(id: "claude", title: "Claude Code",
                    meta: claudeFound ? "\(claudeVersion) · \(claudeIn ? "signed in" : "not signed in")" : "Not installed",
                    ok: claudeIn,
                    fix: !claudeFound ? "brew install --cask claude-code" : (claudeIn ? nil : "claude auth login")),
            ToolRow(id: "gh", title: "GitHub CLI",
                    meta: ghFound ? "gh \(ghVersion) · " + (ghIn ? (login.isEmpty ? "signed in" : "signed in as \(login)") : "not signed in")
                                  : "Not installed",
                    ok: ghIn,
                    fix: !ghFound ? "brew install gh" : (ghIn ? nil : "gh auth login")),
            ToolRow(id: "git", title: "Git and the Command Line Tools",
                    meta: gitReady ? "git \(gitVersion)" : (clt ? "git not found" : "Command Line Tools not installed"),
                    ok: gitReady,
                    fix: gitReady ? nil : "xcode-select --install"),
            ToolRow(id: "gitnexus", title: "GitNexus (optional)",
                    meta: nexus ? "Found" : "Shows reviewers who calls the changed code.",
                    ok: nexus,
                    fix: nexus ? nil : "npm install -g gitnexus"),
        ]
        let status = ToolStatus(claudeSignedIn: claudeIn, ghSignedIn: ghIn, gitReady: gitReady, gitNexus: nexus)
        return Report(rows: rows, status: status)
    }

    /// `claude auth status --json` reports `loggedIn`. Only the boolean is read.
    private static func claudeSignedIn(_ env: [String: String]) -> Bool {
        let text = stdout("claude", ["auth", "status", "--json"], env)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return object["loggedIn"] as? Bool ?? false
    }

    private static func stdout(_ exe: String, _ args: [String], _ env: [String: String]) -> String {
        let r = Shell.run(exe, args, env: env, timeout: 30)
        return r.ok ? r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    private static func words(_ text: String) -> [Substring] {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" })
    }
}

/// The onboarding state machine's view model. The rules are in `OnboardingState`; this class runs the commands behind
/// the steps and publishes what they find. Every config write goes through `ConfigEditor` or `OnboardingState.config`.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var state: OnboardingState
    @Published private(set) var toolRows: [ToolRow] = []
    @Published private(set) var checkingTools = false
    @Published private(set) var repos: [DiscoveredRepo] = []
    @Published private(set) var repoList: RepoListState = .idle
    @Published var search = ""
    @Published var loginText = ""
    /// The amber message under the step's lead.
    @Published var message: String?
    /// The command whose Copy was pressed last, shown as "Copied".
    @Published private(set) var copied: String?
    /// Where an existing config.toml was copied before onboarding replaced it, shown on the final step.
    @Published private(set) var backupNote: String?
    /// PRs of the dry run, as the first sweep step shows them while it runs and after it lands.
    @Published private(set) var liveStrips: [Strip] = []

    let paths: Paths
    /// The config on disk when the window opened, or after "Use my config file". Nil when there is none.
    private(set) var base: Config?

    init(paths: Paths) {
        self.paths = paths
        let existing = try? Config.load(paths)
        base = existing
        state = OnboardingState.initial(existing: existing)
        // A first sweep that failed after its config was written reopens on that step, with its failure.
        state.step = OnboardingState.resumeStep(configExists: existing != nil, failedSweep: OnboardingResume.failedSweep)
        if state.step == .firstSweep, let failure = OnboardingResume.failedSweep {
            state.firstSweep = .failed(failure)
        }
    }

    /// The schedule line on the first sweep step: setup leaves an installed job as it is, and a new job starts paused.
    var scheduleCopy: String {
        guard keepsSchedule else { return "The schedule stays paused until you turn it on." }
        return Pause.isPaused(paths) ? "Your current schedule stays paused." : "Your current schedule stays on."
    }

    private var keepsSchedule: Bool {
        !Pause.pausesOnSetup(jobInstalled: FileManager.default.fileExists(atPath: paths.plistFile))
    }

    /// Snapshot rendering: a model with the given fields and nothing read from disk, run or launched.
    init(fixture: OnboardingState, paths: Paths, tools: [ToolRow] = [], repos: [DiscoveredRepo] = [],
         repoList: RepoListState = .loaded, liveStrips: [Strip] = [], backupNote: String? = nil) {
        self.paths = paths
        base = nil
        state = fixture
        toolRows = tools
        self.repos = repos
        self.repoList = repoList
        self.liveStrips = liveStrips
        self.backupNote = backupNote
    }

    /// True once the first sweep has landed: the rail dot rests on the runway.
    var isLanded: Bool {
        if case .finished = state.firstSweep { return true }
        return false
    }

    // MARK: Navigation

    func advance() {
        guard state.canContinue(from: state.step), let next = state.next(from: state.step) else { return }
        state.step = next
        message = nil
    }

    func goBack() {
        guard let previous = state.back(from: state.step) else { return }
        state.step = previous
        message = nil
    }

    func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = command
    }

    // MARK: Tools

    /// Runs the checks again, or first time. Continue stays disabled until the three required tools pass.
    func checkTools() {
        checkingTools = true
        let env = Runner.environment(paths)
        let home = paths.home
        Task {
            let report = await Task.detached(priority: .userInitiated) {
                OnboardingChecks.run(env: env, home: home)
            }.value
            toolRows = report.rows
            state.tools = report.status
            checkingTools = false
        }
    }

    // MARK: Repos

    /// Lists the user's repos and orgs' repos. Runs off the main thread; a failure shows in place of the list.
    func loadRepos() {
        guard repoList != .loading else { return }
        repoList = .loading
        let env = Runner.environment(paths)
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[DiscoveredRepo], ConfigError> in
                do {
                    return .success(try RepoDiscovery.load(env: env))
                } catch let error as ConfigError {
                    return .failure(error)
                } catch {
                    return .failure(ConfigError(message: "\(error)"))
                }
            }.value
            switch result {
            case .success(let found):
                repos = found
                repoList = .loaded
            case .failure(let error):
                repoList = .failed(error.message)
            }
        }
    }

    /// Every row the list shows: the discovered repos, then any selected slug the list does not have.
    var allRows: [DiscoveredRepo] {
        let known = Set(repos.map(\.slug))
        let extra = state.repos.filter { !known.contains($0) }.map {
            DiscoveredRepo(slug: $0, language: nil, pushedAt: nil, openPRs: nil)
        }
        return repos + extra
    }

    /// The rows after the search, which matches the name.
    var filteredRows: [DiscoveredRepo] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return allRows }
        return allRows.filter { $0.slug.lowercased().contains(query) }
    }

    /// "Go · pushed 12 minutes ago", from what the list knows.
    func meta(for repo: DiscoveredRepo) -> String {
        var parts: [String] = []
        if let language = repo.language { parts.append(language) }
        if let pushed = repo.pushedAt {
            let relative = RelativeDateTimeFormatter().localizedString(for: pushed, relativeTo: Date())
            parts.append("pushed \(relative)")
        }
        return parts.isEmpty ? "No details" : parts.joined(separator: " · ")
    }

    func toggleRepo(_ slug: String) {
        if let index = state.repos.firstIndex(of: slug) {
            state.repos.remove(at: index)
        } else {
            state.repos.append(slug)
        }
    }

    // MARK: Welcome

    /// Picks a config.toml, checks it with `Config.parse`, and copies its text to the config path. A file that does
    /// not validate is reported under the lead and nothing is written. On success the wizard jumps to the first sweep.
    func useConfigFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "toml") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a Glidepath config.toml"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let config = try Config.parse(text, home: paths.home)
            try FileManager.default.createDirectory(atPath: paths.configDir, withIntermediateDirectories: true)
            backupNote = try backupNoteFor(ConfigEditor.backupExisting(paths: paths))
            try text.write(toFile: paths.configFile, atomically: true, encoding: .utf8)
            base = config
            state = OnboardingState.initial(existing: config)
            state.step = .firstSweep
            message = nil
        } catch let error as ConfigError {
            message = error.message
        } catch {
            message = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: Review

    /// Adds a login to "These people…". Validated like the Repos section; a duplicate is named.
    func addLogin() {
        let login = loginText.trimmingCharacters(in: .whitespaces)
        guard !login.isEmpty else { return }
        do {
            _ = try ConfigEditor.validateLogin(login)
        } catch let error as ConfigError {
            message = error.message
            return
        } catch {
            return
        }
        var logins: [String] = []
        if case .logins(let current) = state.authors { logins = current }
        guard !logins.contains(login) else {
            message = "\(login) is already listed"
            return
        }
        state.authors = .logins(logins + [login])
        loginText = ""
        message = nil
    }

    func removeLogin(_ login: String) {
        guard case .logins(let current) = state.authors else { return }
        state.authors = .logins(current.filter { $0 != login })
    }

    // MARK: Schedule

    /// Applies one schedule edit with the same rules as the Schedule section, to the times in this state.
    func editSchedule(_ change: (Config) throws -> Config) {
        let temp = Config(schedule: state.schedule, limits: Limits(), repos: [])
        do {
            state.schedule = try change(temp).schedule
            message = nil
        } catch let error as ConfigError {
            message = error.message
        } catch {
            message = "\(error)"
        }
    }

    /// The sentence the final step shows for a backup, or nil when there was no file to back up.
    private func backupNoteFor(_ backup: String?) -> String? {
        guard let backup else { return nil }
        return "Your previous config was saved to \((backup as NSString).lastPathComponent)."
    }

    // MARK: First sweep

    /// Writes the config, installs the job paused, and runs the dry run of the first repo. Each part runs off the main
    /// thread, and the rows fill in while the dry run works.
    func runFirstSweep() {
        guard state.firstSweep != .running else { return }
        if base == nil && FileManager.default.fileExists(atPath: paths.configFile) {
            state.firstSweep = .failed("config.toml exists but does not parse. Fix it, or choose another with Use my config file.")
            OnboardingResume.failedSweep = OnboardingState.failure(of: state.firstSweep)
            return
        }
        guard let first = state.repos.first else { return }
        // Only when the file was not already backed up by Use my config file this session.
        if backupNote == nil {
            do {
                backupNote = try backupNoteFor(ConfigEditor.backupExisting(paths: paths))
            } catch {
                message = "Could not back up config.toml, so nothing was written: \(error.localizedDescription)"
                return
            }
        }
        let config = state.config(base: base, home: paths.home)
        let env = Runner.environment(paths)
        let paths = self.paths
        let started = Date()
        state.firstSweep = .running
        OnboardingResume.failedSweep = nil
        liveStrips = []
        message = nil

        let poller = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await refreshLive(since: started)
            }
        }
        Task {
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<ShellResult, ConfigError> in
                do {
                    return .success(try OnboardingSetup.run(config: config, paths: paths, env: env))
                } catch let error as ConfigError {
                    return .failure(error)
                } catch {
                    return .failure(ConfigError(message: "\(error.localizedDescription)"))
                }
            }.value
            poller.cancel()
            await refreshLive(since: started)
            switch outcome {
            case .failure(let error):
                state.firstSweep = .failed(error.message)
            case .success(let result) where !result.ok:
                let last = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\n").last.map(String.init) ?? ""
                state.firstSweep = .failed("The dry run of \(first) failed." + (last.isEmpty ? "" : " \(String(last.prefix(200)))"))
            case .success:
                base = config
                let summary = OnboardingSummary.landing(liveStrips, posting: state.posting, repo: first)
                state.firstSweep = .finished(reviews: summary.reviews, summary: summary.text)
            }
            OnboardingResume.failedSweep = OnboardingState.failure(of: state.firstSweep)
        }
    }

    /// Reads the current sweep's run file off the main thread, then shows its PRs here.
    private func refreshLive(since started: Date) async {
        let paths = self.paths
        let run = await Task.detached(priority: .utility) { currentSweepRun(paths: paths, since: started) }.value
        liveStrips = Store.strips(from: run)
    }

    /// Turns the schedule on: unpauses the job and opens Overview.
    func turnOnSchedule() {
        do {
            try Pause.set(false, paths)
            finish()
        } catch {
            message = "Could not turn the schedule on: \(error.localizedDescription)"
        }
    }

    /// Leaves the schedule paused and opens Overview.
    func postNothingYet() {
        do {
            try Pause.set(true, paths)
            finish()
        } catch {
            message = "Could not pause the schedule: \(error.localizedDescription)"
        }
    }

    private func finish() {
        Store.shared.reload()
        WindowRouter.shared.showOnboarding = false
        WindowRouter.shared.section = .overview
    }
}

/// The run file of the sweep that started at or after `started`. Only the run files written since then are candidates
/// (by modification time, from the directory listing), and only the newest of them is read. Runs on a background thread.
func currentSweepRun(paths: Paths, since started: Date) -> RunState? {
    let fm = FileManager.default
    let cutoff = started.addingTimeInterval(-1)
    let newest = ((try? fm.contentsOfDirectory(atPath: paths.runsDir)) ?? [])
        .filter { $0.hasSuffix(".json") }
        .compactMap { name -> (id: String, written: Date)? in
            let id = String(name.dropLast(5))
            guard let written = (try? fm.attributesOfItem(atPath: paths.runFile(id)))?[.modificationDate] as? Date,
                  written >= cutoff else { return nil }
            return (id, written)
        }
        .max { $0.written < $1.written }
    guard let id = newest?.id, let run = try? RunStore(paths: paths).load(id), run.started >= cutoff else { return nil }
    return run
}

/// The pane's width, set by `OnboardingView.pane` so the footer bar can span it.
private struct PaneWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 700
}

extension EnvironmentValues {
    var paneWidth: CGFloat {
        get { self[PaneWidthKey.self] }
        set { self[PaneWidthKey.self] = newValue }
    }
}

/// The footer bar's frame: the pane's width less its 64 pt insets, 44 tall.
struct FooterFrame: ViewModifier {
    @Environment(\.paneWidth) private var paneWidth

    func body(content: Content) -> some View {
        content.frame(width: max(0, paneWidth - 128), height: 44)
    }
}

/// The footer bar: Back flush left when there is one, the step's actions flush right, across the pane's full width.
struct FooterBar<Trailing: View>: View {
    let back: (() -> Void)?
    let trailing: Trailing

    var body: some View {
        HStack(spacing: WinMetrics.s12) {
            if let back {
                WinButton(title: "Back", style: .quiet, action: back)
            }
            Spacer(minLength: 0)
            trailing
        }
        .modifier(FooterFrame())
    }
}
