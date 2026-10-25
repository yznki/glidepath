import SwiftUI
import AppKit

/// The labels and captions of every row. The search reads these, so a row and its search text stay in one place.
enum SettingsCopy {
    struct Row {
        let label: String
        let caption: String
        var text: String { label + " " + caption }
    }

    struct Block: Identifiable {
        let id: String
        let title: String
        let rows: [Row]
    }

    static let strictLabels = ["Relaxed", "Easygoing", "Balanced", "Exacting", "Ruthless"]
    static let strictSentences = [
        "Lets style and small things go.",
        "Flags only what could break.",
        "Bugs, risk and clear design problems.",
        "Also naming, tests and edge cases.",
        "Every nit. Nothing gets through.",
    ]

    static let drafts = Row(label: "Review draft PRs", caption: "Each repo can override this in Repos.")
    static let whenReady = Row(label: "When a review is ready", caption: "Hold for me keeps it until you hold to post.")
    static let strictness = Row(label: "Strictness", caption: "")
    static let reviewModel = Row(label: "Model", caption: "Bigger models read deeper and use more tokens.")
    static let size = Row(label: "Skip PRs larger than", caption: "")
    static let ownPRs = Row(label: "Review my own PRs", caption: "")
    static let bots = Row(label: "Review bot PRs", caption: "Dependabot, Renovate and friends.")
    static let authors = Row(label: "Authors", caption: "Whose PRs get reviewed.")
    static let flags = Row(label: "Look closer at", caption: "Changes under these paths get flagged in the review.")

    static let notify = Row(label: "Notify when reviews land", caption: "")
    static let changesOnly = Row(label: "Only for changes requested", caption: "Approvals land quietly.")
    static let sound = Row(label: "Sound", caption: "Plays when a review lands.")
    static let focus = Row(label: "Respect Focus", caption: "Hold notifications while a Focus is on.")

    static let icon = Row(label: "Icon", caption: "How the menu bar icon looks.")
    static let badge = Row(label: "Badge when reviews wait", caption: "")
    static let shortcut = Row(label: "Open Glidepath", caption: "Click, then press the keys.")
    static let login = Row(label: "Open at login", caption: "Starts Glidepath when you log in.")

    static let signal = Row(label: "Signal colour", caption: "The one colour Glidepath uses: changes requested.")
    static let glass = Row(label: "Glass", caption: "How much the cards blur what is behind them.")
    static let motion = Row(label: "Motion", caption: "Reduced stops the glider and the breathing.")

    static let monthly = Row(label: "Monthly tokens", caption: "")
    static let pause = Row(label: "Pause at budget", caption: "Sweeps stop until the month turns over.")

    static let dryRun = Row(label: "Dry run", caption: "Review everything, post nothing. Good for trying rules.")
    static let codeGraph = Row(label: "Code graph", caption: "GitNexus maps the blast radius of each change.")
    static let checks = Row(label: "Check for updates", caption: "Checks GitHub in the background.")
    static let updates = Row(label: "Updates", caption: "Check now, or install the release on offer.")
    static let files = Row(label: "Files", caption: "The config, the log and the state folder.")
    static let tools = Row(label: "Tools", caption: "Checked live. A missing one shows the command that fixes it.")
    static let reset = Row(label: "Reset all settings", caption: "Repos and history stay.")
    static let uninstall = Row(label: "Uninstall Glidepath", caption: "Removes the job, the skill and the app link.")

    static let reviewing = Block(id: "review", title: "Reviewing",
                                 rows: [drafts, whenReady, strictness, reviewModel, size, ownPRs, bots, authors, flags])
    // Tending. Every caption says "tend", so the search "tend" shows the whole block.
    static let tendOn = Row(label: "Tend my PRs", caption: "Glidepath fixes failing CI on your open PRs in the repos switched on below.")
    static let tendRepos = Row(label: "Tended repos", caption: "Glidepath tends the PRs in the repos switched on here.")
    static let tendPush = Row(label: "Approved fixes", caption: "Push anyway pushes a tended fix at once. Hold the fix keeps it for you.")
    static let tendRounds = Row(label: "Rounds per PR a day", caption: "Each PR gets at most this many tending rounds a day.")
    static let tendAutopilot = Row(label: "Autopilot", caption: "Tending merges, replies and resolves without asking. Hard stops still come to you.")
    static let tendDisagree = Row(label: "When Glidepath disagrees",
                                  caption: "Tending leaves the reply as a draft for you, or posts it and resolves the thread.")
    static let tendAccount = Row(label: "Claude account", caption: "Tending and reviews sign in as this account.")
    static let tendReserve = Row(label: "Usage reserve", caption: "Tending never spends the last share of your 5-hour and weekly windows.")
    static let tendQuiet = Row(label: "Quiet hours", caption: "Heavy tending waits for these hours.")
    static let tending = Block(id: "tending", title: "Tending",
                               rows: [tendOn, tendRepos, tendPush, tendRounds, tendAutopilot, tendDisagree, tendAccount,
                                      tendReserve, tendQuiet])

    static let notifications = Block(id: "notify", title: "Notifications", rows: [notify, changesOnly, sound, focus])
    static let menuBar = Block(id: "menubar", title: "Menu bar", rows: [icon, badge, shortcut, login])
    static let look = Block(id: "look", title: "Look", rows: [signal, glass, motion])
    static let budget = Block(id: "budget", title: "Budget", rows: [monthly, pause])
    static let advanced = Block(id: "advanced", title: "Advanced",
                                rows: [dryRun, codeGraph, checks, updates, files, tools, reset, uninstall])
    static let blocks = [reviewing, tending, notifications, menuBar, look, budget, advanced]
}

/// Settings: the search, the section chips, and six groups of rows. Each switch, segment and slider saves at once
/// through `SettingsModel.commit`; look rows save to UserDefaults.
struct SettingsView: View {
    @ObservedObject var store: Store
    @StateObject private var model: SettingsModel
    @Environment(\.offscreenRender) private var offscreen
    @AppStorage("signalColour") private var signalKey = "amber"
    @AppStorage("glyphStyle") private var glyphStyle = "glider"
    @AppStorage("glyphBadge") private var glyphBadge = true
    @AppStorage("glassBlur") private var glassBlur = 22.0
    @AppStorage("motion") private var motion = "full"

    /// `query` starts the search. Snapshot rendering uses it to show one group.
    init(store: Store, query: String = "") {
        self.store = store
        _model = StateObject(wrappedValue: SettingsModel(query: query))
    }

    private var config: Config? { store.snap.config }
    private var repos: [RepoConfig] { config?.repos ?? [] }

    /// The reason the shortcut is not working: the last save's error, or the shortcut being on but not registered.
    private var hotkeyError: String? {
        if let error = model.rowErrors["hotkey"] { return error }
        guard !store.isFixture, config?.hotkey.isOn ?? true, !GlobalHotkey.shared.registered else { return nil }
        return "Another app already uses \(shortcutText), so Glidepath cannot register it."
    }

    /// The shortcut as the user wrote it, or ⌥⌘G when it is the default.
    private var shortcutText: String {
        if case .custom(let text) = config?.hotkey ?? .on { return text }
        return "⌥⌘G"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleRow(saved: model.saved) {
                model.loadToml(store.paths)
                model.drawerOpen = true
            }
            Group {
                if offscreen {
                    FieldStandIn(text: model.query, placeholder: "Search settings", font: .system(size: 14, weight: .medium),
                                 height: 38, radius: 11, search: true)
                } else {
                    TextField("Search settings", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Gotham.fg)
                        .padding(.horizontal, 14)
                        .frame(height: 38)
                        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Gotham.row))
                        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                }
            }
            .padding(.bottom, 12)
            ScrollViewReader { proxy in
                chips(proxy)
                WinScroll {
                    VStack(alignment: .leading, spacing: 0) {
                        reviewing
                        tending
                        notifications
                        menuBar
                        look
                        budget
                        advanced
                    }
                    .padding(.bottom, WinMetrics.canvasBottom)
                }
            }
        }
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.leading, WinMetrics.canvasLeft)
        .padding(.trailing, WinMetrics.canvasRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .trailing) {
            if model.drawerOpen {
                ConfigDrawer(lines: model.tomlLines, changed: model.tomlChanged) { model.drawerOpen = false }
                    .transition(.move(edge: .trailing))
            }
        }
        .overlay(alignment: .bottom) {
            if let text = model.toastText {
                SettingsToast(text: text)
                    .padding(.bottom, 22)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.standard, value: model.drawerOpen)
        .animation(.easeOut(duration: 0.3), value: model.toastText)
        .onAppear { model.refresh(store) }
        .onReceive(store.$snap) { _ in model.refreshUsed(store) }
        .onChange(of: store.snap.config) { _, _ in model.loadToml(store.paths) }
        .onDisappear { model.stopRecording() }
    }

    // MARK: Chips

    /// The sticky section chips. A chip scrolls its group to the top and stays lit.
    private func chips(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 6) {
            ForEach(SettingsCopy.blocks.filter { model.matches($0) }) { block in
                Button {
                    model.chip = block.id
                    withAnimation(Motion.standard) { proxy.scrollTo("g-" + block.id, anchor: .top) }
                } label: {
                    Text(block.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(model.chip == block.id ? Gotham.fg : Gotham.mute)
                        .padding(.horizontal, 12)
                        .frame(height: 28)
                        .background(Capsule().fill(model.chip == block.id ? Gotham.tint : Gotham.row))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Row helpers

    /// A plain row: shown when it matches the search, with the given control on its right.
    @ViewBuilder
    private func row<C: View>(_ copy: SettingsCopy.Row, error: String? = nil, caption: String? = nil,
                              stacked: Bool = false, @ViewBuilder _ control: @escaping () -> C) -> some View {
        if model.matches(copy) {
            SettingItem(label: copy.label, caption: caption ?? copy.caption, error: error, stacked: stacked, control: control)
        }
    }

    /// A caption that says the repos differ, in place of the usual one.
    private func caption(_ base: String, mixed: Bool) -> String {
        mixed ? "Mixed across repos. Changing it sets them all." : base
    }

    /// True when the repos hold different values.
    private func mixed<T: Equatable>(_ values: [T]) -> Bool {
        guard let first = values.first else { return false }
        return values.contains { $0 != first }
    }

    /// The value every repo shares, or nil when they differ or there are none.
    private func common<T: Equatable>(_ values: [T]) -> T? {
        guard let first = values.first, !mixed(values) else { return nil }
        return first
    }

    /// Repo-wide tags from one list per repo, in order, without repeats.
    private func union(_ lists: [[String]]) -> [String] {
        var out: [String] = []
        for list in lists { for item in list where !out.contains(item) { out.append(item) } }
        return out
    }

    private var loginUnion: [String] { Self.loginUnion(repos) }

    /// Every login listed by any repo, in config order.
    private static func loginUnion(_ repos: [RepoConfig]) -> [String] {
        var out: [String] = []
        for repo in repos {
            if case .logins(let logins) = repo.authors {
                for login in logins where !out.contains(login) { out.append(login) }
            }
        }
        return out
    }

    private func policyTag(_ policy: AuthorPolicy) -> String {
        switch policy {
        case .anyone: return "anyone"
        case .collaborators: return "collaborators"
        case .logins: return "logins"
        }
    }

    private func chooseAuthors(_ tag: String) {
        if tag == "logins" {
            // Repos already on their own list keep it; the others start from the union of every list.
            model.commit("authors", store: store) { config in
                let union = Self.loginUnion(config.repos)
                var out = config
                for repo in config.repos {
                    if case .logins = repo.authors { continue }
                    out = try ConfigEditor.setAuthors(out, slug: repo.slug, .logins(union))
                }
                return out
            }
            return
        }
        let policy: AuthorPolicy = tag == "collaborators" ? .collaborators : .anyone
        model.eachRepo("authors", store: store) { try ConfigEditor.setAuthors($0, slug: $1, policy) }
    }

    /// Adds or removes one login on each repo's own list. Repos not on "Only these" are left alone, and the other logins stay.
    private func editLogin(_ login: String, adding: Bool) {
        model.commit("authors", store: store) { config in
            var out = config
            for repo in config.repos {
                guard case .logins(let logins) = repo.authors else { continue }
                let updated: [String]?
                if adding { updated = logins.contains(login) ? nil : logins + [login] } else { updated = logins.contains(login) ? logins.filter { $0 != login } : nil }
                guard let updated else { continue }
                out = try ConfigEditor.setAuthors(out, slug: repo.slug, .logins(updated))
            }
            return out
        }
    }

    /// The size-skip caption from the open PRs the store has sized: "N of M open PRs would be skipped". Nil when none is sized.
    private func skipCaption(_ maxLines: Double) -> String? {
        let sized = store.strips.compactMap(\.changedLines)
        guard !sized.isEmpty else { return nil }
        let skipped = sized.filter { Double($0) > maxLines }.count
        return "\(skipped) of \(sized.count) open PRs would be skipped."
    }

    private func millions(_ tokens: Int) -> String {
        String(format: "%g", Double(tokens) / 1_000_000) + "M"
    }

    // MARK: Reviewing

    @ViewBuilder private var reviewing: some View {
        if model.matches(SettingsCopy.reviewing) {
            SettingGroup(id: "g-review", title: "Reviewing") {
                row(SettingsCopy.drafts, error: model.rowErrors["drafts"]) {
                    SettingSwitch(isOn: config?.reviewDrafts ?? false, label: "Review draft PRs") {
                        model.commit("drafts", store: store) { ConfigEditor.setReviewDrafts($0, !$0.reviewDrafts) }
                    }
                }
                row(SettingsCopy.whenReady, error: model.rowErrors["posting"],
                    caption: caption(SettingsCopy.whenReady.caption, mixed: mixed(repos.map(\.posting)))) {
                    SettingSegmented(
                        options: [(value: Posting.review, label: "Post review"), (value: .comment, label: "Comment only"),
                                  (value: .draft, label: "Hold for me")],
                        selected: common(repos.map(\.posting))) { posting in
                            model.eachRepo("posting", store: store) { try ConfigEditor.setPosting($0, slug: $1, posting) }
                        }
                }
                if model.matches(SettingsCopy.strictness) {
                    SliderRow(row: SettingsCopy.strictness, error: model.rowErrors["strictness"],
                              committed: Double(Strictness.allCases.firstIndex(of: config?.strictness ?? .balanced) ?? 2),
                              range: 0...4, valueText: { SettingsCopy.strictLabels[Int($0.rounded())] },
                              caption: { SettingsCopy.strictSentences[Int($0.rounded())] }) { value in
                        let level = Strictness.allCases[Int(value.rounded())]
                        model.commit("strictness", store: store) { ConfigEditor.setStrictness($0, level) }
                    }
                }
                row(SettingsCopy.reviewModel, error: model.rowErrors["model"]) {
                    SettingSegmented(
                        options: [(value: ReviewModel.haiku, label: "Haiku"), (value: .sonnet, label: "Sonnet"),
                                  (value: .opus, label: "Opus")],
                        selected: config?.model ?? .opus) { choice in
                            model.commit("model", store: store) { ConfigEditor.setModel($0, choice) }
                        }
                }
                if model.matches(SettingsCopy.size) {
                    SliderRow(row: SettingsCopy.size, error: model.rowErrors["size"],
                              committed: Double(config?.limits.maxChangedLines ?? 3000),
                              range: 100...3000, step: 50, valueText: { "\(Int($0)) lines" },
                              caption: { skipCaption($0) }) { value in
                        model.commit("size", store: store) { try ScheduleEditor.setLimits($0, prs: $0.limits.maxPRsPerRun, lines: Int(value)) }
                    }
                }
                let ownOn = !repos.isEmpty && repos.allSatisfy(\.includeOwn)
                row(SettingsCopy.ownPRs, error: model.rowErrors["ownPRs"],
                    caption: caption("", mixed: mixed(repos.map(\.includeOwn)))) {
                    SettingSwitch(isOn: ownOn, label: "Review my own PRs") {
                        model.eachRepo("ownPRs", store: store) { try ConfigEditor.setRepoIncludeOwn($0, slug: $1, !ownOn) }
                    }
                }
                row(SettingsCopy.bots, error: model.rowErrors["bots"]) {
                    SettingSwitch(isOn: config?.includeBots ?? false, label: "Review bot PRs") {
                        model.commit("bots", store: store) { ConfigEditor.setIncludeBots($0, !$0.includeBots) }
                    }
                }
                row(SettingsCopy.authors, error: model.rowErrors["authors"],
                    caption: caption(SettingsCopy.authors.caption, mixed: mixed(repos.map { policyTag($0.authors) }))) {
                    VStack(alignment: .trailing, spacing: 8) {
                        SettingSegmented(
                            options: [(value: "anyone", label: "Everyone"), (value: "collaborators", label: "Collaborators"),
                                      (value: "logins", label: "Only these")],
                            selected: common(repos.map { policyTag($0.authors) }), onSelect: chooseAuthors)
                        if repos.contains(where: { if case .logins = $0.authors { return true } else { return false } }) {
                            SettingTags(tags: loginUnion, placeholder: "Add login",
                                        onAdd: { login in
                                            guard !loginUnion.contains(login) else { return }
                                            editLogin(login, adding: true)
                                        },
                                        onRemove: { login in editLogin(login, adding: false) })
                        }
                    }
                }
                row(SettingsCopy.flags, error: model.rowErrors["flags"]) {
                    let paths = union(repos.map(\.flagPaths))
                    SettingTags(tags: paths, placeholder: "Add path, Enter",
                                onAdd: { model.addFlag($0, store: store) },
                                onRemove: { model.removeFlag($0, store: store) })
                }
            }
        }
    }

    // MARK: Tending

    /// The tend job's install or removal after the switch is saved. A message when it fails, else nil.
    private func tendJob(_ on: Bool) -> String? {
        do {
            if on { try TendJob.install(paths: store.paths) } else { TendJob.remove(paths: store.paths) }
            return nil
        } catch {
            return "Could not \(on ? "install" : "remove") the tend job: \(error.localizedDescription)"
        }
    }

    @ViewBuilder private var tending: some View {
        if model.matches(SettingsCopy.tending) {
            let tend = config?.tend ?? TendConfig()
            SettingGroup(id: "g-tending", title: "Tending") {
                row(SettingsCopy.tendOn, error: model.rowErrors["tend"]) {
                    SettingSwitch(isOn: tend.enabled, label: "Tend my PRs") {
                        let on = !tend.enabled
                        model.commit("tend", store: store, onSaved: { tendJob(on) }) { ConfigEditor.setTendEnabled($0, on) }
                    }
                }
                if model.matches(SettingsCopy.tendRepos) {
                    ForEach(repos, id: \.slug) { repo in
                        SettingItem(label: repo.slug, error: model.rowErrors["tendRepo-\(repo.slug)"]) {
                            SettingSwitch(isOn: repo.tend, label: "Tend \(repo.slug)") {
                                model.commit("tendRepo-\(repo.slug)", store: store) {
                                    try ConfigEditor.setRepoTend($0, slug: repo.slug, !repo.tend)
                                }
                            }
                        }
                    }
                }
                row(SettingsCopy.tendPush, error: model.rowErrors["tendPush"]) {
                    SettingSegmented(
                        options: [(value: TendPush.always, label: "Push anyway"), (value: .untilApproved, label: "Hold the fix")],
                        selected: tend.push) { choice in
                            model.commit("tendPush", store: store) { ConfigEditor.setTendPush($0, choice) }
                        }
                }
                if model.matches(SettingsCopy.tendRounds) {
                    SliderRow(row: SettingsCopy.tendRounds, error: model.rowErrors["tendRounds"],
                              committed: Double(tend.roundsPerDay), range: 1...10, valueText: { "\(Int($0.rounded()))" }) { value in
                        model.commit("tendRounds", store: store) { try ConfigEditor.setTendRoundsPerDay($0, Int(value.rounded())) }
                    }
                }
                row(SettingsCopy.tendAutopilot, error: model.rowErrors["autopilot"]) {
                    SettingSwitch(isOn: tend.autopilot, label: "Autopilot") {
                        model.commit("autopilot", store: store) { ConfigEditor.setAutopilot($0, !$0.tend.autopilot) }
                    }
                }
                row(SettingsCopy.tendDisagree, error: model.rowErrors["tendDisagree"]) {
                    SettingSegmented(
                        options: [(value: TendDisagree.draft, label: "Draft for me"), (value: .replyResolve, label: "Reply and resolve")],
                        selected: tend.disagree) { choice in
                            model.commit("tendDisagree", store: store) { ConfigEditor.setTendDisagree($0, choice) }
                        }
                }
                if model.matches(SettingsCopy.tendAccount) {
                    let separate = config?.claudeConfigDir != nil
                    SettingItem(label: SettingsCopy.tendAccount.label, caption: model.accountStatus ?? "Checking…",
                                error: model.rowErrors["account"]) {
                        HStack(spacing: 8) {
                            if separate {
                                SettingButton(title: "Sign in…") { model.signIn(store) }
                            }
                            SettingSegmented(
                                options: [(value: false, label: "Same as my claude"), (value: true, label: "Separate account")],
                                selected: separate) { choice in
                                    model.chooseAccount(separate: choice, store: store)
                                }
                        }
                    }
                }
                if model.matches(SettingsCopy.tendReserve) {
                    SliderRow(row: SettingsCopy.tendReserve, error: model.rowErrors["reserve"],
                              committed: Double(tend.usageReserve), range: 0...90, step: 5,
                              valueText: { "\(Int($0.rounded()))%" },
                              caption: { "Tending never spends the last \(Int($0.rounded()))% of your 5-hour and weekly windows." }) { value in
                        model.commit("reserve", store: store) { try ConfigEditor.setUsageReserve($0, Int(value.rounded())) }
                    }
                }
                if model.matches(SettingsCopy.tendQuiet) {
                    SettingItem(label: SettingsCopy.tendQuiet.label, caption: SettingsCopy.tendQuiet.caption,
                                error: model.rowErrors["quiet"]) {
                        QuietHoursField(text: tend.quietHours.text, offscreen: offscreen) { text in
                            model.commit("quiet", store: store) { try ConfigEditor.setQuietHours($0, text) }
                        }
                    }
                }
            }
        }
    }

    // MARK: Notifications

    @ViewBuilder private var notifications: some View {
        if model.matches(SettingsCopy.notifications) {
            SettingGroup(id: "g-notify", title: "Notifications") {
                row(SettingsCopy.notify, error: model.rowErrors["notify"]) {
                    SettingSwitch(isOn: config?.notify ?? true, label: "Notify when reviews land") {
                        model.commit("notify", store: store) { ConfigEditor.setNotify($0, !$0.notify) }
                    }
                }
                row(SettingsCopy.changesOnly, error: model.rowErrors["changesOnly"]) {
                    SettingSwitch(isOn: config?.notifyChangesOnly ?? false, label: "Only for changes requested") {
                        model.commit("changesOnly", store: store) { ConfigEditor.setNotifyChangesOnly($0, !$0.notifyChangesOnly) }
                    }
                }
                row(SettingsCopy.sound, error: model.rowErrors["sound"]) {
                    SettingSegmented(
                        options: NotifySound.allCases.map { (value: $0, label: $0.rawValue.capitalized) },
                        selected: config?.notifySound ?? .glass) { sound in
                            model.preview(sound)
                            model.commit("sound", store: store) { ConfigEditor.setNotifySound($0, sound) }
                        }
                }
                row(SettingsCopy.focus, error: model.rowErrors["focus"]) {
                    SettingSwitch(isOn: config?.respectFocus ?? true, label: "Respect Focus") {
                        model.commit("focus", store: store) { ConfigEditor.setRespectFocus($0, !$0.respectFocus) }
                    }
                }
            }
        }
    }

    // MARK: Menu bar

    @ViewBuilder private var menuBar: some View {
        if model.matches(SettingsCopy.menuBar) {
            SettingGroup(id: "g-menubar", title: "Menu bar") {
                row(SettingsCopy.icon) {
                    HStack(spacing: 8) {
                        glyphTile("glider", "Glider")
                        glyphTile("dot", "Dot")
                        glyphTile("count", "Count")
                    }
                }
                row(SettingsCopy.badge) {
                    SettingSwitch(isOn: glyphBadge, label: "Badge when reviews wait") { glyphBadge = !glyphBadge }
                }
                row(SettingsCopy.shortcut, error: hotkeyError,
                    caption: model.recording ? "Press the keys. Esc cancels." : nil) {
                    HStack(spacing: 12) {
                        SettingKeycap(text: (config?.hotkey.isOn ?? true) ? shortcutText : "Off",
                                      recording: model.recording) {
                            model.startRecording(store)
                        }
                        SettingSwitch(isOn: config?.hotkey.isOn ?? true, label: "Open Glidepath shortcut") {
                            model.toggleHotkey(store)
                        }
                    }
                }
                row(SettingsCopy.login, error: model.rowErrors["login"]) {
                    SettingSwitch(isOn: model.loginOn, label: "Open at login") { model.toggleLogin(store) }
                }
            }
        }
    }

    /// One menu bar icon choice: a tile with its face, raised when chosen.
    private func glyphTile(_ key: String, _ label: String) -> some View {
        let on = glyphStyle == key
        return Button { glyphStyle = key } label: {
            VStack(spacing: 7) {
                glyphFace(key)
                    .frame(height: 18)
                Text(label.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(Gotham.mute)
            }
            .frame(width: 78, height: 64)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Gotham.row))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(on ? Gotham.fg : Gotham.edge, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    @ViewBuilder private func glyphFace(_ key: String) -> some View {
        switch key {
        case "dot": Circle().fill(Gotham.fg).frame(width: 9, height: 9)
        case "count": Text("2").font(.system(size: 12.5, weight: .semibold)).monospacedDigit().foregroundStyle(Gotham.fg)
        default: Image(systemName: "paperplane.fill").font(.system(size: 15)).foregroundStyle(Gotham.fg)
        }
    }

    // MARK: Look

    @ViewBuilder private var look: some View {
        if model.matches(SettingsCopy.look) {
            SettingGroup(id: "g-look", title: "Look") {
                row(SettingsCopy.signal) {
                    HStack(spacing: 10) {
                        ForEach(["amber", "crimson", "ice", "mono"], id: \.self) { key in
                            Button { signalKey = key } label: {
                                Circle()
                                    .fill(Gotham.signal(key))
                                    .frame(width: 28, height: 28)
                                    .shadow(color: Gotham.signal(key).opacity(0.6), radius: 7)
                                    .overlay {
                                        if signalKey == key {
                                            Circle().strokeBorder(Gotham.fg, lineWidth: 2).padding(-4)
                                        }
                                    }
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(key)
                        }
                    }
                }
                row(SettingsCopy.glass) {
                    HStack(spacing: 12) {
                        SettingSliderTrack(value: $glassBlur, range: 0...40, step: 1)
                        Text(glassBlur == 0 ? "Clear" : "\(Int(glassBlur))px")
                            .font(.system(size: 13))
                            .monospacedDigit()
                            .foregroundStyle(Gotham.fg)
                            .frame(minWidth: 96, alignment: .trailing)
                    }
                }
                row(SettingsCopy.motion) {
                    SettingSegmented(options: [(value: "full", label: "Full"), (value: "reduced", label: "Reduced")],
                                     selected: motion) { motion = $0 }
                }
            }
        }
    }

    // MARK: Budget

    @ViewBuilder private var budget: some View {
        if model.matches(SettingsCopy.budget) {
            SettingGroup(id: "g-budget", title: "Budget") {
                if model.matches(SettingsCopy.monthly) {
                    BudgetRow(row: SettingsCopy.monthly, error: model.rowErrors["budget"],
                              committed: config?.monthlyTokens ?? 0, used: model.usedTokens) { tokens in
                        model.commit("budget", store: store) { try ConfigEditor.setMonthlyTokens($0, tokens) }
                    }
                }
                row(SettingsCopy.pause, error: model.rowErrors["pauseAtBudget"]) {
                    SettingSwitch(isOn: config?.pauseAtBudget ?? true, label: "Pause at budget") {
                        model.commit("pauseAtBudget", store: store) { ConfigEditor.setPauseAtBudget($0, !$0.pauseAtBudget) }
                    }
                }
            }
        }
    }

    // MARK: Advanced

    @ViewBuilder private var advanced: some View {
        if model.matches(SettingsCopy.advanced) {
            SettingGroup(id: "g-advanced", title: "Advanced") {
                row(SettingsCopy.dryRun, error: model.rowErrors["dryRun"]) {
                    SettingSwitch(isOn: config?.dryRun ?? false, label: "Dry run") {
                        model.commit("dryRun", store: store) { ConfigEditor.setDryRun($0, !$0.dryRun) }
                    }
                }
                let graphOn = repos.contains { $0.gitnexus != .off }
                row(SettingsCopy.codeGraph, error: model.rowErrors["codeGraph"],
                    caption: caption(SettingsCopy.codeGraph.caption, mixed: mixed(repos.map(\.gitnexus)))) {
                    SettingSwitch(isOn: graphOn, label: "Code graph") {
                        let turnOn = !graphOn
                        // Turning on sets off repos to auto; turning off sets every repo off. Repos already in the target state keep their mode.
                        model.commit("codeGraph", store: store) { config in
                            var out = config
                            for repo in config.repos {
                                if turnOn, repo.gitnexus == .off {
                                    out = try ConfigEditor.setGitNexus(out, slug: repo.slug, .auto)
                                } else if !turnOn, repo.gitnexus != .off {
                                    out = try ConfigEditor.setGitNexus(out, slug: repo.slug, .off)
                                }
                            }
                            return out
                        }
                    }
                }
                row(SettingsCopy.checks, error: model.rowErrors["autoUpdates"]) {
                    SettingSwitch(isOn: config?.checkUpdates ?? true, label: "Check for updates") {
                        model.commit("autoUpdates", store: store) { ConfigEditor.setCheckUpdates($0, !$0.checkUpdates) }
                    }
                }
                row(SettingsCopy.updates, error: model.rowErrors["updates"], stacked: true) {
                    updatesControl
                }
                row(SettingsCopy.files, error: model.rowErrors["advanced"]) {
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(spacing: 8) {
                            SettingButton(title: "Open config file") { model.openConfig(store.paths) }
                            SettingButton(title: "Open log") { store.openLog() }
                        }
                        HStack(spacing: 8) {
                            SettingButton(title: "Reveal state folder") { model.revealStateFolder(store.paths) }
                            SettingButton(title: "Show config.toml") {
                                model.loadToml(store.paths)
                                model.drawerOpen = true
                            }
                        }
                    }
                }
                row(SettingsCopy.tools, error: model.rowErrors["tools"], stacked: true) {
                    toolsControl
                }
                if model.matches(SettingsCopy.reset) {
                    SettingItem(label: SettingsCopy.reset.label, caption: SettingsCopy.reset.caption,
                                error: model.rowErrors["reset"]) {
                        HoldButton(title: "Hold to reset", doneTitle: "Settings reset", tint: Gotham.signal(signalKey)) {
                            model.resetSettings(store)
                        }
                        .frame(width: 190)
                        .id(model.resetCount)
                    }
                }
                row(SettingsCopy.uninstall, error: model.rowErrors["uninstall"], stacked: true) {
                    VStack(alignment: .leading, spacing: 8) {
                        Button("Uninstall Glidepath…") { confirmUninstall() }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Gotham.mute)
                            .disabled(model.uninstalling)
                        if let note = model.uninstallNote {
                            Text(note)
                                .font(.system(size: 12))
                                .foregroundStyle(Gotham.mute)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    /// The version, the check, and the update on offer (the one filled control on the row).
    private var updatesControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text("Glidepath \(Version.current)")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .foregroundStyle(Gotham.fg)
                SettingButton(title: "Check now", enabled: !store.snap.updateChecking) {
                    store.checkForUpdates(manual: true)
                }
            }
            if let update = store.availableUpdate {
                SettingButton(title: "Update to \(update.latest)…", prominent: true,
                              enabled: store.snap.updatePhase != .updating) {
                    confirmUpdate(update)
                }
            }
            if store.snap.updatePhase == .failed {
                Text("Update failed. See the log.")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.fg)
            } else if let note = store.snap.updateNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
            }
        }
    }

    /// The missing checks that have a command: what "Fix all in Terminal" runs.
    private var fixable: [Checks.Item] { model.tools.filter { !$0.ok && $0.command != nil } }

    /// The onboarding tools list, live: each check with its status, and the fix with Copy for anything missing.
    private var toolsControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.tools.isEmpty {
                Text("Checking…")
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.mute)
            } else {
                ForEach(Array(model.tools.enumerated()), id: \.offset) { _, item in
                    toolLine(item)
                }
            }
            HStack(spacing: 12) {
                SettingButton(title: "Check again", enabled: !model.checking) { model.runChecks(store.paths) }
                if !fixable.isEmpty {
                    SettingButton(title: "Fix all in Terminal", prominent: true) { model.fix(fixable, store.paths) }
                }
            }
        }
    }

    /// One check: a mark (filled when it passes, hollow when not), the name, and for a missing one the fix with Copy.
    private func toolLine(_ item: Checks.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(item.ok ? Gotham.fg : Color.clear)
                    .overlay(Circle().strokeBorder(item.ok ? Color.clear : Gotham.skipped, lineWidth: 1.5))
                Image(systemName: item.ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(item.ok ? Gotham.void : Gotham.fg)
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.fg)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.ok {
                    HStack(alignment: .center, spacing: 12) {
                        Text(item.fix)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Gotham.mute)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        SettingButton(title: "Copy") { model.copy(item.fix) }
                        if item.command != nil {
                            SettingButton(title: "Fix") { model.fix([item], store.paths) }
                        }
                    }
                }
            }
        }
    }

    /// The same confirm as the popover's Update: Homebrew installs in place; anything else opens the release page.
    private func confirmUpdate(_ update: UpdateCache) {
        guard store.updatesWithBrew else {
            if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update Glidepath to \(update.latest)?"
        alert.informativeText = "Homebrew rebuilds it from source, which takes about a minute. The app restarts when it's done."
            + (store.snap.running ? " A sweep is running, so the update starts when it ends." : "")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.startUpdate()
    }

    /// Names what goes, then runs `glidepath uninstall` only on confirm.
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Uninstall Glidepath?"
        alert.informativeText = "This removes the scheduled job, the skill in ~/.claude/skills/glidepath, the app link in "
            + "~/Applications, and the login item. Your config and state stay. Clones are not touched. "
            + "Glidepath itself comes from Homebrew: run brew uninstall glidepath to remove it."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.uninstall(store)
    }
}

/// The title row: "Settings" at 24 pt, the Saved stamp for the controls, and the config.toml drawer button. Observes the
/// stamp itself, because a flash on a child object does not redraw the parent.
private struct TitleRow: View {
    @ObservedObject var saved: SavedFlash
    let onToml: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Gotham.fg)
                .frame(height: 32, alignment: .leading)
            SavedStamp(shown: saved.shown)
            Spacer(minLength: 12)
            SettingButton(title: "config.toml", action: onToml)
        }
        .padding(.bottom, 24)
    }
}

/// A slider row whose caption can follow the value being dragged. The draft is owned here, so the config is written
/// once, on release.
private struct SliderRow: View {
    let row: SettingsCopy.Row
    let error: String?
    let committed: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    let valueText: (Double) -> String
    var caption: ((Double) -> String?)? = nil
    let commit: (Double) -> Void
    @StateObject private var draft = SliderDraft()

    var body: some View {
        let shown = draft.value ?? committed
        SettingItem(label: row.label, caption: caption?(shown) ?? row.caption, error: error) {
            SettingSlider(draft: draft, committed: committed, range: range, step: step, valueText: valueText, commit: commit)
        }
        .onChange(of: committed) { _, _ in draft.value = nil }
    }
}

/// The budget row: the ring and the slider in millions. Index 0 is no budget; each step is 0.5M tokens.
private struct BudgetRow: View {
    let row: SettingsCopy.Row
    let error: String?
    let committed: Int
    let used: Int
    let commit: (Int) -> Void
    @StateObject private var draft = SliderDraft()

    private static let step = 500_000

    var body: some View {
        let index = draft.value ?? Double(committed / BudgetRow.step)
        let tokens = Int(index.rounded()) * BudgetRow.step
        let fraction: Double? = tokens > 0 ? Double(used) / Double(tokens) : nil
        SettingItem(label: row.label,
                    caption: tokens > 0
                        ? "\(millions(used)) used this month of \(millions(tokens))."
                        : "No budget set. Scheduled sweeps run without a limit.",
                    error: error) {
            HStack(spacing: 14) {
                BudgetRing(fraction: fraction)
                SettingSlider(draft: draft, committed: Double(committed / BudgetRow.step), range: 0...40, step: 1,
                              valueText: { value in
                                  let steps = Int(value.rounded())
                                  return steps == 0 ? "No budget" : millions(steps * BudgetRow.step)
                              },
                              commit: { value in commit(Int(value.rounded()) * BudgetRow.step) })
            }
        }
        .onChange(of: committed) { _, _ in draft.value = nil }
    }

    private func millions(_ tokens: Int) -> String {
        String(format: "%g", Double(tokens) / 1_000_000) + "M"
    }
}
