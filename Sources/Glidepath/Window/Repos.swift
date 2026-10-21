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
        case .draft: return "Saves a draft you post from Glidepath or Reviews. Nothing reaches GitHub until you post it."
        }
    }
}

/// The Repos section (v1.2 mockup 7-repos): the configured repos in a 260 pt list, beside the selected repo's settings.
/// Each control saves at once through `ConfigEditor`, then the store reloads. Invalid input writes nothing and shows
/// its message in amber under the control it came from.
struct ReposView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ReposModel()

    private var repos: [RepoConfig] { store.snap.config?.repos ?? [] }

    /// The repo the detail shows: the selected one, or the first while none is selected or the selected one is gone.
    private var selected: RepoConfig? {
        repos.first { $0.slug == model.selectedSlug } ?? repos.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 260)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(WinTheme.line).frame(width: 1)
                }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $model.addingRepo) {
            AddRepoSheet(store: store, model: model)
        }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Repos")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(WinTheme.text)
                .frame(height: 32, alignment: .leading)
                .padding(.horizontal, WinMetrics.s20)
            WinScroll {
                VStack(spacing: 0) {
                    ForEach(repos, id: \.slug) { repo in
                        listRow(repo)
                    }
                }
                .padding(.horizontal, WinMetrics.s12)
            }
            .frame(maxHeight: .infinity)
            .padding(.top, WinMetrics.s16)
            WinButton(title: "Add a repo…", style: .link) { model.openAddRepo() }
                .frame(height: 40, alignment: .leading)
                .padding(.horizontal, WinMetrics.s20)
                .padding(.bottom, WinMetrics.canvasBottom)
        }
        .padding(.top, WinMetrics.titlebarZone)
    }

    /// A 56 pt row: the avatar, the slug (13 medium) over the posting mode (12 faint). The selected row takes the
    /// active fill.
    private func listRow(_ repo: RepoConfig) -> some View {
        let on = selected?.slug == repo.slug
        return Button {
            model.select(repo.slug)
        } label: {
            HStack(spacing: WinMetrics.s12) {
                Text(initials(repo.slug))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WinTheme.muted)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(WinTheme.avatar))
                VStack(alignment: .leading, spacing: 0) {
                    Text(repo.slug)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WinTheme.text)
                        .lineLimit(1)
                        .frame(height: 20, alignment: .leading)
                    Text(repo.posting.modeLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .frame(height: 16, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, WinMetrics.s8)
            .frame(height: 56)
            .background(RoundedRectangle(cornerRadius: 10).fill(on ? WinTheme.active : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Two letters for the avatar: the first of the owner and the first of the name, as "la" for lumen/api.
    private func initials(_ slug: String) -> String {
        slug.split(separator: "/").map { String($0.prefix(1)) }.joined().lowercased()
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let repo = selected {
            RepoDetail(repo: repo, store: store, model: model, saved: model.saved)
        } else {
            VStack(alignment: .leading, spacing: WinMetrics.s16) {
                Text("No repos yet. Add one to start reviewing.")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                WinButton(title: "Add a repo…", style: .outline) { model.openAddRepo() }
            }
            .padding(.top, WinMetrics.titlebarZone)
            .padding(.leading, WinMetrics.canvasLeft)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
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
                        .foregroundStyle(WinTheme.text)
                        .frame(height: 32, alignment: .leading)
                    SavedStamp(shown: model.saved.shown)
                }
                if !subline.isEmpty {
                    Text(subline)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .monospacedDigit()
                        .frame(height: 16, alignment: .leading)
                }
            }
            Spacer(minLength: WinMetrics.s16)
            WinButton(title: "Review now", style: .outline) { store.runNow(repo: repo.slug) }
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
            Text(repo.posting.preview)
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.muted)
                .padding(.horizontal, WinMetrics.s12)
                .padding(.vertical, 10)
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
        if model.commit("authors", store: store, { try ConfigEditor.setAuthors($0, slug: repo.slug, .logins(next)) }) {
            model.loginText = ""
            model.editingLogins = false
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
                    .foregroundStyle(repo.rules == nil ? WinTheme.faint : WinTheme.text)
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
            guard model.commit("rules", store: store, { try ConfigEditor.setRules($0, slug: repo.slug, path: path) }) else { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private var codeGraphSection: some View {
        section("Code graph", "Shows reviewers who calls the changed code.", error: model.rowErrors["gitnexus"]) {
            HStack(spacing: WinMetrics.s12) {
                WinToggle(isOn: repo.gitnexusRefresh) {
                    model.commit("gitnexus", store: store) { try ConfigEditor.setGitNexusRefresh($0, slug: repo.slug, !repo.gitnexusRefresh) }
                }
                Text("Refresh the GitNexus index before each sweep")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.text)
            }
            .frame(height: 32)
        }
    }

    private var flagsSection: some View {
        section("Flagged paths", "Reviews that touch these ask for an extra approval.", error: model.rowErrors["flags"]) {
            HStack(spacing: WinMetrics.s8) {
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
        if model.commit("flags", store: store, { try ConfigEditor.addFlaggedPath($0, slug: repo.slug, path: path) }) {
            model.flagText = ""
            model.addingFlag = false
        }
    }

    /// The note posted with a flagged review. Click to edit; Enter saves.
    @ViewBuilder
    private var noteRow: some View {
        if model.editingNote {
            TextField("Note", text: $model.noteText)
                .winField()
                .onSubmit {
                    if model.commit("flags", store: store, { try ConfigEditor.setFlagNote($0, slug: repo.slug, note: model.noteText) }) {
                        model.editingNote = false
                    }
                }
        } else {
            Button {
                model.noteText = repo.flagNote
                model.editingNote = true
            } label: {
                Text("Note: \(repo.flagNote)")
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
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
                .foregroundStyle(WinTheme.text)
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

    var body: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s16) {
            Text("Add a repo")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WinTheme.text)
            Text("Enter owner/name, as it appears on GitHub.")
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.faint)
            TextField("owner/name", text: $model.addText)
                .winField()
                .onSubmit(add)
            if let error = model.rowErrors["add"] {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.amberInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: WinMetrics.s12) {
                Spacer(minLength: 0)
                WinButton(title: "Cancel", style: .link) { model.addingRepo = false }
                WinButton(title: "Add", style: .primary, small: true, action: add)
            }
        }
        .padding(WinMetrics.s24)
        .frame(width: 420)
        .background(WinTheme.ground)
    }

    private func add() {
        let slug = model.addText.trimmingCharacters(in: .whitespaces)
        let repo = RepoConfig(slug: slug, clone: ConfigEditor.defaultClone(slug: slug, home: store.paths.home))
        guard model.commit("add", store: store, { try ConfigEditor.addRepo($0, repo) }) else { return }
        model.addingRepo = false
        model.select(slug)
    }
}

/// The Repos section's state: the selected repo, the amber message for each row, the Saved stamp, and the open sheet
/// and fields. Every save goes through `commit`.
@MainActor
final class ReposModel: ObservableObject {
    @Published var selectedSlug: String?
    /// The message for each control's row, kept until that row saves.
    @Published var rowErrors: [String: String] = [:]
    /// True for 2 s after a successful save.
    let saved = SavedFlash()
    @Published var addingRepo = false
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
        rowErrors["add"] = nil
        addingRepo = true
    }

    /// Applies one edit to the saved config and writes it. On success the store reloads and the Saved stamp shows.
    /// On failure the message goes to `row` and nothing is written.
    @discardableResult
    func commit(_ row: String, store: Store, _ change: (Config) throws -> Config) -> Bool {
        guard let config = store.snap.config else {
            rowErrors[row] = "No config yet. Run glidepath init."
            return false
        }
        do {
            let next = try change(config)
            try ConfigEditor.save(next, paths: store.paths)
            rowErrors[row] = nil
            flashSaved()
            store.reload()
            return true
        } catch let error as ConfigError {
            rowErrors[row] = error.message
        } catch {
            rowErrors[row] = "Could not save: \(error.localizedDescription)"
        }
        return false
    }

    /// Removes a repo, then selects the first one left.
    func remove(_ slug: String, store: Store) {
        if commit("remove", store: store, { try ConfigEditor.removeRepo($0, slug: slug) }) {
            selectedSlug = nil
        }
    }

    private func flashSaved() {
        saved.flash()
    }
}
