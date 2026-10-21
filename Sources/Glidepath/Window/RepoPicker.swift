import SwiftUI

/// The repos GitHub lists for the user and orgs, shared by onboarding and the Repos "Add a repo…" sheet. Loads in two
/// phases, each off the main thread: the list first, then the open PR counts. The last complete list is kept for
/// 10 minutes, so reopening either screen is instant.
@MainActor
final class RepoCatalog: ObservableObject {
    static let shared = RepoCatalog()

    @Published private(set) var repos: [DiscoveredRepo] = []
    @Published private(set) var repoList: RepoListState = .idle

    private static var cache: (at: Date, repos: [DiscoveredRepo])?
    private static let cacheTTL: TimeInterval = 600
    /// True from the start of phase 1 until phase 2 lands. A second `load` meanwhile does nothing.
    private var inFlight = false

    /// Snapshot rendering only: the list the screens show, in place of a listing.
    func preset(_ repos: [DiscoveredRepo], _ list: RepoListState) {
        self.repos = repos
        repoList = list
    }

    func load(paths: Paths) {
        guard !inFlight else { return }
        if let cache = Self.cache, Date().timeIntervalSince(cache.at) < Self.cacheTTL {
            repos = cache.repos
            repoList = .loaded
            return
        }
        inFlight = true
        repoList = .loading
        let env = Runner.environment(paths)
        Task {
            defer { inFlight = false }
            let listed = await Task.detached(priority: .userInitiated) { () -> Result<RepoDiscovery.Listing, ConfigError> in
                do {
                    return .success(try RepoDiscovery.loadRepos(env: env))
                } catch let error as ConfigError {
                    return .failure(error)
                } catch {
                    return .failure(ConfigError(message: "\(error)"))
                }
            }.value
            let listing: RepoDiscovery.Listing
            switch listed {
            case .success(let found):
                listing = found
            case .failure(let error):
                repoList = .failed(error.message)
                return
            }
            repos = listing.repos
            repoList = .loaded
            let counts = await Task.detached(priority: .userInitiated) {
                RepoDiscovery.loadOpenCounts(owners: listing.owners, env: env)
            }.value
            repos = RepoDiscovery.applyOpenCounts(counts.counts, searched: counts.searched, to: repos)
            Self.cache = (Date(), repos)
        }
    }
}

/// The repo picker: a search field, then one checkbox row per repo, with the PR count. Onboarding and the Repos
/// "Add a repo…" sheet both use it. `selected` rows are checked; `locked` rows are checked and cannot be changed.
struct RepoPicker: View {
    @ObservedObject var catalog: RepoCatalog
    @Binding var search: String
    let selected: Set<String>
    var locked: Set<String> = []
    let toggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(catalog.repoList == .loaded ? "Search \(catalog.repos.count) repos" : "Search repos", text: $search)
                .winField()
            list
                .padding(.top, WinMetrics.s8)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// Every row the list shows: the listed repos, then any selected slug the list does not have.
    private var rows: [DiscoveredRepo] {
        let known = Set(catalog.repos.map(\.slug))
        let extra = selected.filter { !known.contains($0) }.sorted().map {
            DiscoveredRepo(slug: $0, language: nil, pushedAt: nil, openPRs: nil)
        }
        let all = catalog.repos + extra
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return all }
        return all.filter { $0.slug.lowercased().contains(query) }
    }

    @ViewBuilder
    private var list: some View {
        switch catalog.repoList {
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
            let rows = rows
            if rows.isEmpty {
                Text("No repos match \"\(search)\".")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.faint)
            } else {
                WinScroll {
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.slug) { index, repo in
                            row(repo, first: index == 0)
                        }
                    }
                }
            }
        }
    }

    /// A 56 pt row: checkbox, slug over language and last push, and the open PR count. Its rule sits inside the row.
    private func row(_ repo: DiscoveredRepo, first: Bool) -> some View {
        let on = selected.contains(repo.slug)
        let isLocked = locked.contains(repo.slug)
        return Button {
            toggle(repo.slug)
        } label: {
            HStack(spacing: WinMetrics.s16) {
                RepoCheckbox(on: on)
                VStack(alignment: .leading, spacing: 0) {
                    Text(repo.slug)
                        .font(.system(size: 14))
                        .foregroundStyle(WinTheme.text)
                        .lineLimit(1)
                    Text(Self.meta(for: repo))
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
            .opacity(isLocked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    /// "Go · pushed 12 minutes ago", from what the list knows.
    static func meta(for repo: DiscoveredRepo) -> String {
        var parts: [String] = []
        if let language = repo.language { parts.append(language) }
        if let pushed = repo.pushedAt {
            let relative = RelativeDateTimeFormatter().localizedString(for: pushed, relativeTo: Date())
            parts.append("pushed \(relative)")
        }
        return parts.isEmpty ? "No details" : parts.joined(separator: " · ")
    }
}
