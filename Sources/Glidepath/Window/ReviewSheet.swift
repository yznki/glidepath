import SwiftUI

/// One author's open PR count across the configured repos, for the Review sheet's list.
struct AuthorCount: Identifiable, Equatable {
    let login: String
    let count: Int
    var id: String { login }
}

/// Where the Review sheet's author list stands.
enum AuthorListing: Equatable {
    case idle, loading, loaded
    case failed(String)
}

/// The "Review a PR or author…" sheet's state: the fields, the author list it loads, and the amber message for the
/// last Review press. Owned by `NowView`, the same way `ReposModel` is owned by `ReposView`.
@MainActor
final class ReviewSheetModel: ObservableObject {
    enum Mode: Equatable { case pr, author }

    @Published var open = false
    @Published var mode: Mode = .pr
    /// The config slug the PR number is read against. The first configured repo when the sheet opens.
    @Published var repo = ""
    @Published var prText = ""
    @Published var search = ""
    @Published var selectedAuthor: String?
    @Published private(set) var authors: [AuthorCount] = []
    @Published private(set) var listing: AuthorListing = .idle
    /// The configured repos whose open PRs could not be listed.
    @Published private(set) var failedRepos: [String] = []
    /// The message under the form, from the last Review press.
    @Published var error: String?
    /// Bumped by each open and each load, so a load that finishes after either one is not applied.
    private var generation = 0

    /// Opens the sheet with empty fields, the PR form, and the first configured repo. The author list loads again on
    /// the first switch to "An author", so it is never older than this open.
    func show(repos: [String]) {
        generation += 1
        mode = .pr
        repo = repos.first ?? ""
        prText = ""
        search = ""
        selectedAuthor = nil
        error = nil
        listing = .idle
        authors = []
        failedRepos = []
        open = true
    }

    /// Lists every configured repo's open PRs off the main thread, and counts them by author. A second call while the
    /// list is loading or loaded does nothing.
    func load(store: Store) {
        guard listing == .idle else { return }
        generation += 1
        let current = generation
        let repos = store.snap.config?.repos.map(\.slug) ?? []
        let env = Runner.environment(store.paths)
        listing = .loading
        Task {
            let found = await Task.detached(priority: .userInitiated) { () -> (authors: [AuthorCount], failed: [String]) in
                var counts: [String: (login: String, count: Int)] = [:]
                var failed: [String] = []
                for slug in repos {
                    guard let prs = try? Runner.openPRs(slug, env: env) else {
                        failed.append(slug)
                        continue
                    }
                    // The CLI rejects a login that fails this, so the list leaves it out.
                    for pr in prs where (try? ConfigEditor.validateLogin(pr.author)) != nil {
                        // Logins are case-insensitive on GitHub: count them together, keep the first spelling seen.
                        counts[pr.author.lowercased(), default: (login: pr.author, count: 0)].count += 1
                    }
                }
                let authors = counts.values
                    .map { AuthorCount(login: $0.login, count: $0.count) }
                    .sorted { $0.count != $1.count ? $0.count > $1.count : $0.login < $1.login }
                return (authors, failed)
            }.value
            guard current == generation else { return }
            authors = found.authors
            failedRepos = found.failed
            listing = found.authors.isEmpty && !found.failed.isEmpty ? .failed("Could not list open PRs") : .loaded
        }
    }

    /// The target the form asks for, or the message to show. In PR mode a GitHub PR link is read as it is; a bare
    /// number is read against the picked repo. The repo must be one of `repos`, spelled as the config spells it.
    func target(config repos: [String]) -> Result<ReviewTarget, ConfigError> {
        guard !repos.isEmpty else { return .failure(ConfigError(message: "No repos configured")) }
        switch mode {
        case .pr:
            let text = prText.trimmingCharacters(in: .whitespaces)
            guard let pr = ReviewTarget.parsePR([text]) ?? ReviewTarget.parsePR([repo, text]) else {
                return .failure(ConfigError(message: "Type a PR number or paste a GitHub PR link"))
            }
            guard let configured = repos.first(where: { $0.caseInsensitiveCompare(pr.slug) == .orderedSame }) else {
                return .failure(ConfigError(message: "\(pr.slug) is not in your repos"))
            }
            return .success(.pr(slug: configured, n: pr.n))
        case .author:
            guard let login = selectedAuthor else { return .failure(ConfigError(message: "Pick an author")) }
            return .success(.author(login))
        }
    }
}

/// The "Review a PR or author…" sheet, opened from Now. "A PR" reviews one PR by number or link. "An author" lists the
/// open PRs of every configured repo by author, and reviews all of one author's. Styled like `AddRepoSheet`.
struct ReviewNowSheet: View {
    @ObservedObject var store: Store
    @ObservedObject var model: ReviewSheetModel

    private var repos: [String] { store.snap.config?.repos.map(\.slug) ?? [] }

    /// The authors the search keeps, in the list's order.
    private var shown: [AuthorCount] {
        let query = model.search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return model.authors }
        return model.authors.filter { $0.login.lowercased().contains(query) }
    }

    /// The open PR count of the picked author, for the primary button's label.
    private var selectedCount: Int? {
        model.authors.first { $0.login == model.selectedAuthor }?.count
    }

    /// A sweep or a dry run holds the run lock, so a review cannot start.
    private var busy: Bool { store.snap.running || store.snap.dryRunning }

    var body: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s16) {
            Text("Review now")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Gotham.fg)
            WinSegmented(
                segments: [
                    WinSegmented<ReviewSheetModel.Mode>.Segment(value: .pr, title: "A PR"),
                    WinSegmented<ReviewSheetModel.Mode>.Segment(value: .author, title: "An author"),
                ],
                selected: model.mode
            ) { mode in
                model.mode = mode
            }
            if model.mode == .pr {
                prFields
            } else {
                authorFields
            }
            if let error = model.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.amberInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: WinMetrics.s12) {
                if busy {
                    Text("A sweep is running")
                        .font(.system(size: 12))
                        .foregroundStyle(Gotham.mute)
                }
                Spacer(minLength: 0)
                WinButton(title: "Cancel", style: .link) { model.open = false }
                WinButton(title: primaryTitle, style: .primary, small: true, action: submit)
                    .disabled(busy)
            }
        }
        .padding(WinMetrics.s24)
        .frame(width: 520)
        .background(WinTheme.ground)
        .onChange(of: model.mode) { _, mode in
            if mode == .author { model.load(store: store) }
        }
        .onChange(of: model.search) { _, _ in
            // A picked author the search hides is no longer the one the button reviews.
            if let picked = model.selectedAuthor, !shown.contains(where: { $0.login == picked }) {
                model.selectedAuthor = nil
            }
        }
    }

    private var prFields: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s8) {
            Picker("Repo", selection: $model.repo) {
                ForEach(repos, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            TextField("PR number or GitHub link", text: $model.prText)
                .winField()
                .onSubmit(submit)
        }
    }

    private var authorFields: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s8) {
            TextField("Search authors", text: $model.search)
                .winField()
            WinScroll {
                VStack(spacing: 0) {
                    authorList
                }
            }
            .frame(height: 260, alignment: .top)
            if !model.failedRepos.isEmpty {
                Text("Could not list PRs in \(model.failedRepos.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var authorList: some View {
        switch model.listing {
        case .idle, .loading:
            muted("Listing open PRs…")
        case .failed(let text):
            muted(text)
        case .loaded:
            if model.authors.isEmpty {
                muted("No open PRs in your repos.")
            } else if shown.isEmpty {
                muted("No authors match \"\(model.search)\".")
            } else {
                ForEach(shown) { author in
                    authorRow(author)
                }
            }
        }
    }

    /// A 44 pt row: avatar, login, and the open PR count. The picked row takes the row fill and a check.
    private func authorRow(_ author: AuthorCount) -> some View {
        let on = model.selectedAuthor == author.login
        return Button {
            model.selectedAuthor = author.login
        } label: {
            HStack(spacing: WinMetrics.s12) {
                AvatarView(login: author.login, size: 24)
                Text(author.login)
                    .font(.system(size: 14))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                Spacer(minLength: WinMetrics.s8)
                Text("\(author.count) open")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .monospacedDigit()
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Gotham.fg)
                }
            }
            .padding(.horizontal, WinMetrics.s12)
            .frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Gotham.row : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func muted(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Gotham.mute)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, WinMetrics.s8)
    }

    private var primaryTitle: String {
        guard model.mode == .author else { return "Review" }
        guard let count = selectedCount else { return "Review" }
        return "Review \(count) PR\(count == 1 ? "" : "s")"
    }

    /// Turns the form into a target. A bad form shows its message; a good one asks, and closes the sheet once the
    /// review starts. A cancel leaves the form as it was.
    private func submit() {
        switch model.target(config: repos) {
        case .failure(let error):
            model.error = error.message
        case .success(let target):
            guard Confirm.review(store, target) else { return }
            model.error = nil
            model.open = false
        }
    }
}
