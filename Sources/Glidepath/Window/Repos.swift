import SwiftUI
import AppKit

extension Posting {
    /// The posting mode as the list and the segmented control name it.
    var modeLabel: String {
        switch self {
        case .comment: return "Comment"
        case .review: return "Full review"
        case .draft: return "Draft first"
        }
    }

    /// The one-line preview under the control: what lands on the pull request.
    var preview: String {
        switch self {
        case .comment: return "Leaves comments on the lines, with no verdict. Shown as a comment by yznki."
        case .review: return "Approves or requests changes, with comments on the lines. Shown as Changes requested by yznki."
        case .draft: return "Saves a draft you post from Glidepath or Reviews. Nothing posts until you do."
        }
    }
}

/// The Repos section (prototype `#rp`): the configured repos as one grouped list. Each row has its draft-PR control
/// (Default, On, Off), saved at once through `ConfigEditor`. A row opens the repo's settings in a sheet.
struct ReposView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ReposModel()

    private var repos: [RepoConfig] { store.snap.config?.repos ?? [] }

    /// The repo the sheet and the menu commands act on.
    private var selected: RepoConfig? {
        repos.first { $0.slug == model.selectedSlug }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WinMetrics.s12) {
                Text("Repos")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Gotham.fg)
                Spacer(minLength: 0)
                addButton
            }
            .padding(.bottom, WinMetrics.s16)
            WinScroll {
                VStack(alignment: .leading, spacing: WinMetrics.s16) {
                    if repos.isEmpty {
                        Text("No repos yet. Add one to start reviewing.")
                            .font(.system(size: 13))
                            .foregroundStyle(Gotham.mute)
                    } else {
                        group
                    }
                }
                .padding(.bottom, WinMetrics.canvasBottom)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.bottom, 26)
        .sheet(isPresented: $model.addingRepo) {
            AddRepoSheet(store: store, model: model)
        }
        .sheet(isPresented: $model.detailOpen) {
            if let repo = selected {
                VStack(spacing: 0) {
                    HStack {
                        Spacer()
                        Button("Done") { model.detailOpen = false }
                            .buttonStyle(.plain)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Gotham.fg)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(Gotham.row))
                            .keyboardShortcut(.cancelAction)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    RepoDetail(repo: repo, store: store, model: model, saved: model.saved)
                }
                .frame(width: 720, height: 640)
                .background(Gotham.void)
            }
        }
        .onChange(of: model.addingRepo) { _, open in
            ShortcutContext.shared.repoSheetOpen = open
        }
        .onChange(of: model.detailOpen) { _, open in
            ShortcutContext.shared.repoSelected = open
        }
        .onDisappear {
            ShortcutContext.shared.repoSheetOpen = false
            ShortcutContext.shared.repoSelected = false
        }
        .onReceive(WindowRouter.shared.$pending.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeAction()
        }
        .onKeyPress(keys: ["e"], phases: .down) { press in
            // ⌘E edits the rules of the repo the sheet shows, or of the first repo in the list.
            guard press.modifiers == [.command], !TextFocus.isEditing else { return .ignored }
            WindowRouter.shared.deliver(.editRules, section: nil)
            return .handled
        }
    }

    // MARK: Header and actions

    private var addButton: some View {
        Button {
            model.openAddRepo()
        } label: {
            Text("Add repo")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Gotham.fg)
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Capsule().fill(Gotham.row))
                .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Add Repo, Find (the add sheet holds the repo search) and Review This Repo Now.
    private func takeAction() {
        guard let action = WindowRouter.shared.take([.addRepo, .find, .reviewRepoNow]) else { return }
        switch action {
        case .addRepo, .find:
            model.openAddRepo()
        case .reviewRepoNow:
            if let slug = selected?.slug, !store.snap.running { Confirm.run(store, repo: slug) }
        default:
            break
        }
    }

    // MARK: List

    /// The grouped list: one row per repo, a hairline between rows.
    private var group: some View {
        VStack(spacing: 0) {
            ForEach(Array(repos.enumerated()), id: \.element.slug) { index, repo in
                if index > 0 {
                    Rectangle().fill(Gotham.edge).frame(height: 1)
                }
                repoRow(repo)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Gotham.row))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
    }

    private func repoRow(_ repo: RepoConfig) -> some View {
        let error = model.rowErrors[Self.draftsRow(repo.slug)]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: WinMetrics.s12) {
                Button {
                    model.select(repo.slug)
                    model.detailOpen = true
                } label: {
                    HStack(spacing: WinMetrics.s12) {
                        Text(initials(repo.slug))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Gotham.mute)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Gotham.tint))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(repo.slug)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Gotham.fg)
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                Text("Draft PRs")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Gotham.mute)
                                dots(repo.slug)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                draftSegments(repo)
            }
            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.signal(signalKey))
            }
        }
        .padding(.horizontal, WinMetrics.s16)
        .padding(.vertical, WinMetrics.s12)
        .frame(minHeight: 60)
    }

    @AppStorage("signalColour") private var signalKey = "amber"

    /// One dot per PR of the current run in this repo: silver for approved, signal for changes, hollow for the rest.
    private func dots(_ slug: String) -> some View {
        HStack(spacing: 4) {
            ForEach(store.strips.filter { $0.repo == slug && !$0.draft }) { strip in
                Circle()
                    .fill(strip.verdict == .approve ? Gotham.approve : strip.verdict == .changes ? Gotham.signal(signalKey) : Gotham.skipped)
                    .frame(width: 6, height: 6)
            }
        }
    }

    /// The draft-PR control: Default (with the global value), On, Off. Its value is the repo's `review_drafts`.
    private func draftSegments(_ repo: RepoConfig) -> some View {
        let global = store.snap.config?.reviewDrafts ?? false
        let options: [(Bool?, String)] = [(nil, "Default (\(global ? "on" : "off"))"), (true, "On"), (false, "Off")]
        return HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = repo.reviewDrafts == option.0
                Button {
                    setDrafts(repo, option.0)
                } label: {
                    Text(option.1)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(on ? Gotham.fg : Gotham.mute)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(on ? Gotham.tint : Color.clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Gotham.row))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
        .fixedSize()
    }

    /// Saves one repo's draft setting through the same commit path as the detail's controls.
    private func setDrafts(_ repo: RepoConfig, _ value: Bool?) {
        guard repo.reviewDrafts != value else { return }
        let slug = repo.slug
        model.commit(Self.draftsRow(slug), store: store) { try ConfigEditor.setRepoReviewDrafts($0, slug: slug, value) }
    }

    /// The key a row's save error is kept under.
    static func draftsRow(_ slug: String) -> String { "drafts|\(slug)" }

    /// Two letters for the avatar: the first of the owner and the first of the name, as "la" for lumen/api.
    private func initials(_ slug: String) -> String {
        slug.split(separator: "/").map { String($0.prefix(1)) }.joined().lowercased()
    }
}

/// The selected repo's settings: the title row, then one row per setting, each saved as it changes.
struct RepoDetail: View {
    let repo: RepoConfig
    @ObservedObject var store: Store
    @ObservedObject var model: ReposModel
    /// Observed here too, so the Saved stamp redraws when a save flashes it.
    @ObservedObject var saved: SavedFlash

    private enum AuthorChoice: Hashable { case collaborators, anyone, people }

    var body: some View {
        WinScroll {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                postingSection
                authorsSection
                rulesSection
                codeGraphSection
                flagsSection
                removeSection
            }
            .padding(.bottom, WinMetrics.canvasBottom)
        }
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.leading, WinMetrics.canvasLeft)
        .padding(.trailing, WinMetrics.canvasRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onReceive(WindowRouter.shared.$pending.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeAction()
        }
        .alert("Remove \(repo.slug) from Glidepath?", isPresented: $model.confirmRemove) {
            Button("Remove", role: .destructive) { model.remove(repo.slug, store: store) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its config is removed; reviews already posted stay on GitHub.")
        }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .top, spacing: WinMetrics.s16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: WinMetrics.s12) {
                    Text(repo.slug)
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(Gotham.fg)
                        .frame(height: 32, alignment: .leading)
                    SavedStamp(shown: model.saved.shown)
                }
                if !subline.isEmpty {
                    Text(subline)
                        .font(.system(size: 12))
                        .foregroundStyle(Gotham.mute)
                        .monospacedDigit()
                        .frame(height: 16, alignment: .leading)
                }
            }
            Spacer(minLength: WinMetrics.s16)
            WinButton(title: "Review now", style: .outline) { Confirm.run(store, repo: repo.slug) }
                .disabled(store.snap.running)
        }
        .padding(.bottom, WinMetrics.s16)
    }

    /// "N open PRs · last reviewed 1:04 PM", from the last sweep's record of this repo. Parts the record lacks are left out.
    private var subline: String {
        let state = store.snap.run?.repos.first { $0.slug == repo.slug }
        var parts: [String] = []
        if let state { parts.append("\(state.prs.count) open PRs") }
        if let posted = state?.prs.compactMap(\.posted).max() {
            parts.append("last reviewed \(posted.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Sections

    private var postingSection: some View {
        section("How reviews post", "What lands on the pull request.", error: model.rowErrors["posting"]) {
            WinSegmented(
                segments: [Posting.comment, .review, .draft].map {
                    WinSegmented<Posting>.Segment(value: $0, title: $0.modeLabel)
                },
                selected: repo.posting
            ) { mode in
                model.commit("posting", store: store) { try ConfigEditor.setPosting($0, slug: repo.slug, mode) }
            }
            previewText(repo.posting.preview)
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .padding(.horizontal, WinMetrics.s12)
                .padding(.vertical, 10)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(WinTheme.surface))
                .padding(.top, WinMetrics.s8)
        }
    }

    private var authorChoice: AuthorChoice {
        if model.editingLogins { return .people }
        switch repo.authors {
        case .collaborators: return .collaborators
        case .anyone: return .anyone
        case .logins: return .people
        }
    }

    private var logins: [String] {
        if case .logins(let logins) = repo.authors { return logins }
        return []
    }

    private var authorsSection: some View {
        section("Whose PRs", "Your own PRs are never reviewed.", error: model.rowErrors["authors"]) {
            WinSegmented(
                segments: [
                    WinSegmented<AuthorChoice>.Segment(value: .collaborators, title: "Collaborators"),
                    WinSegmented<AuthorChoice>.Segment(value: .anyone, title: "Anyone"),
                    WinSegmented<AuthorChoice>.Segment(value: .people, title: "These people…"),
                ],
                selected: authorChoice
            ) { choice in
                guard choice != authorChoice else { return }
                switch choice {
                case .collaborators:
                    model.editingLogins = false
                    model.commit("authors", store: store) { try ConfigEditor.setAuthors($0, slug: repo.slug, .collaborators) }
                case .anyone:
                    model.editingLogins = false
                    model.commit("authors", store: store) { try ConfigEditor.setAuthors($0, slug: repo.slug, .anyone) }
                case .people:
                    // Nothing is saved until the first login is added: an empty list is not a valid config.
                    model.rowErrors["authors"] = nil
                    model.editingLogins = true
                }
            }
            if authorChoice == .people {
                loginEditor
            }
        }
    }

    /// The login list: chips with ×, and a field that adds a login on Enter.
    private var loginEditor: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s8) {
            if !logins.isEmpty {
                HStack(spacing: WinMetrics.s8) {
                    ForEach(logins, id: \.self) { login in
                        chip(login, mono: false) {
                            let rest = logins.filter { $0 != login }
                            model.commit("authors", store: store) { try ConfigEditor.setAuthors($0, slug: repo.slug, .logins(rest)) }
                        }
                    }
                }
            }
            TextField("login", text: $model.loginText)
                .winField()
                .frame(width: 220)
                .onSubmit(addLogin)
        }
        .padding(.top, WinMetrics.s8)
    }

    private func addLogin() {
        let login = model.loginText.trimmingCharacters(in: .whitespaces)
        guard !login.isEmpty else { return }
        guard !logins.contains(login) else {
            model.rowErrors["authors"] = "\(login) is already listed"
            return
        }
        let next = logins + [login]
        model.commit("authors", store: store, then: { [model] ok in
            guard ok else { return }
            model.loginText = ""
            model.editingLogins = false
        }) { try ConfigEditor.setAuthors($0, slug: repo.slug, .logins(next)) }
    }

    /// Edit rules (⌘E) and Remove repo (⌘⌫). Remove still asks first.
    private func takeAction() {
        guard let action = WindowRouter.shared.take([.editRules, .removeRepo]) else { return }
        switch action {
        case .editRules:
            editRules(repo.rules ?? ConfigEditor.defaultRulesPath(slug: repo.slug, paths: store.paths))
        case .removeRepo:
            model.confirmRemove = true
        default:
            break
        }
    }

    private var rulesSection: some View {
        let path = repo.rules ?? ConfigEditor.defaultRulesPath(slug: repo.slug, paths: store.paths)
        let subtitle = repo.rulesMode == .extend
            ? "Your team's bar, on top of the built-in rubric."
            : "Your team's bar replaces the built-in rubric."
        return section("Review rules", subtitle, error: model.rowErrors["rules"]) {
            HStack(spacing: WinMetrics.s12) {
                Text(tilde(path))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(repo.rules == nil ? Gotham.mute : Gotham.fg)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, WinMetrics.s12)
                    .frame(height: 32, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(WinTheme.surface))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WinTheme.control, lineWidth: 1))
                WinButton(title: "Edit", style: .outline) { editRules(path) }
            }
            WinButton(title: repo.rulesMode == .extend ? "Replace the built-in rubric" : "Extend the built-in rubric",
                      style: .link) {
                let mode: RulesMode = repo.rulesMode == .extend ? .replace : .extend
                model.commit("rules", store: store) { try ConfigEditor.setRulesMode($0, slug: repo.slug, mode) }
            }
            .padding(.top, WinMetrics.s8)
        }
    }

    /// Opens the rules file in the default editor. A missing file is created from a one-line template, and a repo
    /// without a rules path is given the default one.
    private func editRules(_ path: String) {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: path) {
                try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
                let template = "# Team review rules for \(repo.slug). Added to the built-in rubric.\n"
                try Data(template.utf8).write(to: URL(fileURLWithPath: path))
            }
        } catch {
            model.rowErrors["rules"] = "Could not create \(path): \(error.localizedDescription)"
            return
        }
        if repo.rules == nil {
            model.commit("rules", store: store, then: { ok in
                if ok { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
            }) { try ConfigEditor.setRules($0, slug: repo.slug, path: path) }
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        }
    }

    private var codeGraphSection: some View {
        section("Code graph", "Shows reviewers who calls the changed code.", error: model.rowErrors["gitnexus"]) {
            HStack(spacing: WinMetrics.s12) {
                WinToggle(isOn: repo.gitnexusRefresh) {
                    model.commit("gitnexus", store: store) { try ConfigEditor.setGitNexusRefresh($0, slug: repo.slug, !repo.gitnexusRefresh) }
                }
                Text("Refresh the GitNexus index before each sweep")
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.fg)
            }
            .frame(height: 32)
        }
    }

    /// The preview with "Changes requested" in semibold amber, as the mockup's `.prev b`.
    private func previewText(_ text: String) -> Text {
        let parts = text.components(separatedBy: "Changes requested")
        guard parts.count == 2 else { return Text(text) }
        return Text(parts[0])
            + Text("Changes requested").fontWeight(.semibold).foregroundColor(WinTheme.amberInk)
            + Text(parts[1])
    }

    private var flagsSection: some View {
        section("Flagged paths", "Reviews that touch these ask for an extra approval.", error: model.rowErrors["flags"]) {
            AnyLayout(FlowRow()) {
                ForEach(repo.flagPaths, id: \.self) { path in
                    chip(path, mono: true) {
                        model.commit("flags", store: store) { try ConfigEditor.removeFlaggedPath($0, slug: repo.slug, path: path) }
                    }
                }
                if model.addingFlag {
                    TextField("infra/", text: $model.flagText)
                        .winField()
                        .frame(width: 200)
                        .onSubmit(addFlag)
                } else {
                    WinButton(title: "Add path…", style: .link) { model.addingFlag = true }
                }
            }
            noteRow
                .padding(.top, WinMetrics.s8)
        }
    }

    private func addFlag() {
        let path = model.flagText.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            model.addingFlag = false
            return
        }
        model.commit("flags", store: store, then: { [model] ok in
            guard ok else { return }
            model.flagText = ""
            model.addingFlag = false
        }) { try ConfigEditor.addFlaggedPath($0, slug: repo.slug, path: path) }
    }

    /// The note posted with a flagged review. Click to edit; Enter saves.
    @ViewBuilder
    private var noteRow: some View {
        if model.editingNote {
            TextField("Note", text: $model.noteText)
                .winField()
                .onSubmit {
                    let note = model.noteText
                    model.commit("flags", store: store, then: { [model] ok in
                        if ok { model.editingNote = false }
                    }) { try ConfigEditor.setFlagNote($0, slug: repo.slug, note: note) }
                }
        } else {
            Button {
                model.noteText = repo.flagNote
                model.editingNote = true
            } label: {
                Text("Note: \(repo.flagNote)")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
            }
            .buttonStyle(.plain)
        }
    }

    private var removeSection: some View {
        section("Remove repo", "Stops Glidepath reviewing this repo.", error: model.rowErrors["remove"]) {
            Button("Remove repo…") { model.confirmRemove = true }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WinTheme.red)
                .frame(height: 32, alignment: .leading)
        }
    }

    // MARK: Pieces

    /// One setting: the 200 pt label column and the control column, with a rule above (base.css `.sec`). The label's
    /// first line is centred on a 32 pt control row.
    private func section<Control: View>(_ title: String, _ detail: String, error: String?,
                                        @ViewBuilder control: () -> Control) -> some View {
        SettingRow(title: title, detail: detail, error: error, control: control)
    }

    /// A chip (base.css `.chip`): 28 tall, raised fill, a × that removes it.
    private func chip(_ text: String, mono: Bool, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12, design: mono ? .monospaced : .default))
                .foregroundStyle(Gotham.fg)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Gotham.mute)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WinMetrics.s12)
        .frame(height: 28)
        .fixedSize()
        .background(Capsule().fill(WinTheme.raised))
    }

    /// The home folder shown as ~, as the rules path reads in the list.
    private func tilde(_ path: String) -> String {
        let home = store.paths.home
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }
}

/// The "Add a repo…" sheet: an owner/name, validated when added. The onboarding picker replaces it later.
struct AddRepoSheet: View {
    @ObservedObject var store: Store
    @ObservedObject var model: ReposModel
    @ObservedObject private var catalog = RepoCatalog.shared

    /// Repos already in the config: checked and locked.
    private var configured: Set<String> { Set(store.snap.config?.repos.map(\.slug) ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s16) {
            Text("Add repos")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Gotham.fg)
            RepoPicker(catalog: catalog, search: $model.pickerSearch, selected: configured.union(model.picked),
                       locked: configured, toggle: toggle)
                .frame(height: 300)
            if let error = model.rowErrors["add"] {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.amberInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: WinMetrics.s8) {
                Text("Or type owner/name")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                HStack(spacing: WinMetrics.s8) {
                    TextField("owner/name", text: $model.addText)
                        .winField()
                        .onSubmit(addTyped)
                    WinButton(title: "Add", style: .outline, small: true, action: addTyped)
                }
            }
            HStack(spacing: WinMetrics.s12) {
                Spacer(minLength: 0)
                WinButton(title: "Cancel", style: .link) { model.addingRepo = false }
                WinButton(title: model.picked.count == 1 ? "Add 1 repo" : "Add \(model.picked.count) repos", style: .primary, small: true,
                          action: addPicked)
                    .disabled(model.picked.isEmpty)
            }
        }
        .padding(WinMetrics.s24)
        .frame(width: 520)
        .background(WinTheme.ground)
        .onAppear { catalog.load(paths: store.paths) }
    }

    private func toggle(_ slug: String) {
        guard !configured.contains(slug) else { return }
        model.picked = model.picked.symmetricDifference([slug])
    }

    private func addPicked() {
        add(model.picked.sorted())
    }

    private func addTyped() {
        add([model.addText.trimmingCharacters(in: .whitespaces)])
    }

    /// Adds the repos with the new-repo defaults: drafts held for posting, and reviews from collaborators.
    private func add(_ slugs: [String]) {
        let home = store.paths.home
        model.commit("add", store: store, then: { [model] ok in
            guard ok else { return }
            model.addingRepo = false
            if let first = slugs.first { model.select(first) }
        }) { config in
            try slugs.reduce(config) { config, slug in
                try ConfigEditor.addRepo(config, RepoConfig(slug: slug, clone: ConfigEditor.defaultClone(slug: slug, home: home),
                                                            posting: .draft, authors: .collaborators))
            }
        }
    }
}

/// The Repos section's state: the selected repo, the amber message for each row, the Saved stamp, and the open sheet
/// and fields. Every save goes through `commit`.
@MainActor
final class ReposModel: ObservableObject {
    @Published var selectedSlug: String?
    /// The settings sheet for `selectedSlug` is open.
    @Published var detailOpen = false
    /// The message for each control's row, kept until that row saves.
    @Published var rowErrors: [String: String] = [:]
    /// True for 2 s after a successful save.
    let saved = SavedFlash()
    @Published var addingRepo = false
    /// Repos picked in the Add sheet and not yet added.
    @Published var picked: Set<String> = []
    @Published var pickerSearch = ""
    @Published var addText = ""
    @Published var confirmRemove = false
    @Published var editingLogins = false
    @Published var loginText = ""
    @Published var addingFlag = false
    @Published var flagText = ""
    @Published var editingNote = false
    @Published var noteText = ""

    /// Selects a repo and drops any open field or message from the last one.
    func select(_ slug: String) {
        selectedSlug = slug
        rowErrors = [:]
        editingLogins = false
        loginText = ""
        addingFlag = false
        flagText = ""
        editingNote = false
    }

    func openAddRepo() {
        addText = ""
        picked = []
        pickerSearch = ""
        rowErrors["add"] = nil
        addingRepo = true
    }

    /// Applies one edit to config.toml as it is on disk now, and writes it off the main actor. On success the Saved
    /// stamp shows; on failure the message goes to `row`. The store reloads either way. `done` gets the outcome.
    func commit(_ row: String, store: Store, then done: @escaping (Bool) -> Void = { _ in },
                _ change: @escaping @Sendable (Config) throws -> Config) {
        let paths = store.paths
        Task {
            let ok: Bool
            do {
                try await ConfigWriter.shared.apply(paths: paths, change: change) { try ConfigEditor.save($0, paths: paths) }
                rowErrors[row] = nil
                flashSaved()
                ok = true
            } catch let error as ConfigError {
                rowErrors[row] = error.message
                ok = false
            } catch {
                rowErrors[row] = "Could not save: \(error.localizedDescription)"
                ok = false
            }
            store.reload()
            done(ok)
        }
    }

    /// Removes a repo, then selects the first one left.
    func remove(_ slug: String, store: Store) {
        commit("remove", store: store, then: { [weak self] ok in
            if ok {
                self?.selectedSlug = nil
                self?.detailOpen = false
            }
        }) {
            try ConfigEditor.removeRepo($0, slug: slug)
        }
    }

    private func flashSaved() {
        saved.flash()
    }
}

/// Lays its children left to right and wraps a full row onto the next, so chips and the add link never truncate.
struct FlowRow: Layout {
    var spacing: CGFloat = WinMetrics.s8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
