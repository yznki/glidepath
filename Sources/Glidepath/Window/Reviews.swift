import SwiftUI

/// The History section: every run as a card, newest first, under day headings. A reviewed PR's row opens its flight
/// recorder sheet. Runs are read by `ReviewsModel`; the cards are `RunCard`s, shared with Now.
struct HistoryView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ReviewsModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("History")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Gotham.fg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, WinMetrics.s16)
            WinScroll {
                VStack(alignment: .leading, spacing: 0) {
                if model.runs.isEmpty {
                    Text("No reviews to show.")
                        .font(.system(size: 13))
                        .foregroundStyle(Gotham.mute)
                        .padding(.top, WinMetrics.s8)
                } else {
                    ForEach(model.days) { group in
                        capLabel(ReviewsModel.dayTitle(group.day))
                            .padding(.top, WinMetrics.s8)
                            .padding(.bottom, 10)
                        ForEach(group.runs, id: \.id) { run in
                            RunCard(run: run, running: store.snap.running && run.id == store.snap.run?.id,
                                    sweep: model.sweep(for: run.id), store: store) { stripID in
                                model.open(runID: run.id, stripID: stripID)
                            }
                        }
                    }
                }
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.bottom, 26)
        .onAppear {
            model.load(store)
            takeFocus()
        }
        .onReceive(store.$snap) { _ in model.load(store) }
        .onReceive(WindowRouter.shared.$reviewFocus.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeFocus()
        }
        // The open sheet's draft flag can change without its id changing (a post or discard reloads the sweeps).
        .onChange(of: model.opened?.id) { _ in ShortcutContext.shared.setReview(model.opened) }
        .onChange(of: model.opened?.draft) { _ in ShortcutContext.shared.setReview(model.opened) }
        .onReceive(model.$sweeps) { _ in ShortcutContext.shared.setReview(model.opened) }
        .onDisappear { ShortcutContext.shared.setReview(nil) }
        .sheet(item: $model.opened) { row in
            ReviewSheet(row: row, text: store.reviewText(runId: row.runId, slug: row.repo, n: row.number), store: store) {
                model.opened = nil
            }
        }
    }

    /// Opens the review a Now row or the popover asked for.
    private func takeFocus() {
        guard let id = WindowRouter.shared.reviewFocus else { return }
        WindowRouter.shared.reviewFocus = nil
        model.focus(id)
    }
}

/// One PR's result in one run: a verdict, a held draft, a skip, or No result (the run finished without a verdict).
/// Carried-over rows are left out, since their run is listed where they were decided.
struct ReviewRow: Identifiable {
    let runId: String
    let repo: String
    let number: Int
    let author: String?
    let title: String?
    let reason: String?
    let verdict: Verdict?
    let draft: Bool
    let skipReason: String?
    let changedLines: Int?
    let head: String?
    let flagged: Bool
    let tokens: Int
    /// The run's length, from its start to its finish. nil while it runs.
    let duration: TimeInterval?
    /// When the review was posted, from its text record. nil while it is a draft, and for reviews from before 1.2.
    let postedAt: Date?
    /// How far the PR got in its run: gather, review, check or post.
    let stage: Stage

    var id: String { "\(runId)|\(repo)#\(number)" }
    /// The key the store uses for a PR's draft actions.
    var stripID: String { "\(repo)#\(number)" }
    var tooLarge: Bool { skipReason == "size" }
    /// The row as the store's post, discard and skip summary see it.
    var strip: Strip {
        Strip(repo: repo, number: number, author: author, title: title, reason: reason, stage: 4, active: false,
              verdict: verdict, tokens: tokens, draft: draft, skipReason: skipReason, changedLines: changedLines)
    }

    /// "repo #n · author · draft", or "posted", or the size or skip reason.
    var metaText: String {
        var parts = ["\(repo) #\(number)"]
        if let author { parts.append(author) }
        if draft {
            parts.append("waiting")
        } else if postedAt != nil {
            parts.append("posted")
        } else if tooLarge {
            parts.append("\((changedLines ?? 0).formatted()) lines")
        } else if verdict == .skipped {
            parts.append(reason ?? "skipped")
        }
        return parts.joined(separator: " · ")
    }
}

/// One run with its rows, as the History and Now sections read them. Carried-over rows are left out.
struct ReviewSweep: Identifiable {
    let id: String
    let started: Date
    let isReview: Bool
    let duration: TimeInterval?
    /// The rows, in run order.
    var rows: [ReviewRow]

    /// `posted` gives when a PR's review was posted, from its text record: the text store in the app, the fixture in
    /// snapshots. The text itself is not kept here.
    init(run: RunState, posted: (_ slug: String, _ n: Int) -> Date?) {
        let length = run.finished.map { $0.timeIntervalSince(run.started) }
        id = run.id
        started = run.started
        isReview = run.kind == "review"
        duration = length
        rows = run.repos.flatMap { repo in
            repo.prs.compactMap { pr -> ReviewRow? in
                // A PR a finished run left without a verdict is a No result row.
                guard pr.carriedFrom == nil,
                      pr.verdict != nil || pr.draft == true || pr.skipReason != nil || run.finished != nil else {
                    return nil
                }
                return ReviewRow(
                    runId: run.id, repo: repo.slug, number: pr.n, author: pr.author, title: pr.title,
                    reason: PRFilter.displayReason(pr.reason), verdict: pr.verdict, draft: pr.draft == true, skipReason: pr.skipReason,
                    changedLines: pr.changedLines, head: pr.head, flagged: pr.flagged == true, tokens: pr.tokens,
                    duration: length,
                    postedAt: posted(repo.slug, pr.n), stage: pr.stage)
            }
        }
    }
}

/// The runs one day started, under that day's heading in History.
struct DayRuns: Identifiable {
    let day: Date
    let runs: [RunState]

    var id: Date { day }
}

/// Loads the newest runs from disk and holds the sheet's open review. Runs are kept newest first, and their reviews
/// are read with them.
@MainActor
final class ReviewsModel: ObservableObject {
    nonisolated static let sweepLimit = 50

    /// The newest runs, newest first.
    @Published private(set) var runs: [RunState] = []
    @Published private(set) var sweeps: [ReviewSweep] = []
    /// The review the sheet shows.
    @Published var opened: ReviewRow?
    /// A PR asked for before the runs loaded, opened when they arrive. The run id is nil when any run will do.
    private var pendingOpen: (runID: String?, stripID: String)?
    private var loadTask: Task<Void, Never>?

    /// Keeps the newest 50 runs. Live, the run files are read off the main actor, after a 300 ms pause: a burst of
    /// store changes costs one read, and a read still waiting when the next change lands is cancelled. Fixtures load at
    /// once, since snapshot rendering reads them synchronously.
    /// ponytail: decodes every run file on each load; index the runs if the folder grows large.
    func load(_ store: Store) {
        loadTask?.cancel()
        if store.isFixture {
            let newest = Self.newest(store.allRuns())
            show(newest, Self.sweeps(from: newest) { runId, slug, n in
                store.reviewText(runId: runId, slug: slug, n: n)?.postedDate
            })
            return
        }
        let paths = store.paths
        loadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let loaded = await Task.detached(priority: .utility) { () -> ([RunState], [ReviewSweep]) in
                let newest = Self.newest(RunStore(paths: paths).loadAll())
                return (newest, Self.sweeps(from: newest) { runId, slug, n in
                    ReviewText.read(paths, runId: runId, slug: slug, n: n)?.postedDate
                })
            }.value
            guard !Task.isCancelled else { return }
            self?.show(loaded.0, loaded.1)
        }
    }

    private func show(_ newest: [RunState], _ loaded: [ReviewSweep]) {
        runs = newest
        sweeps = loaded
        if let pending = pendingOpen, !loaded.isEmpty {
            pendingOpen = nil
            opened = Self.row(runID: pending.runID, stripID: pending.stripID, in: loaded)
        }
    }

    /// Opens a PR's review as a run card asks: the card's own run first, else the newest run that has the PR. Before
    /// the runs load, the open waits for them.
    func open(runID: String?, stripID: String) {
        guard !sweeps.isEmpty else {
            pendingOpen = (runID, stripID)
            return
        }
        opened = Self.row(runID: runID, stripID: stripID, in: sweeps)
    }

    /// Opens a PR from the newest run that has it, as the popover and Now's held drafts ask.
    func focus(_ stripID: String) {
        open(runID: nil, stripID: stripID)
    }

    /// The loaded reviews of one run, when they have loaded.
    func sweep(for runID: String) -> ReviewSweep? {
        sweeps.first { $0.id == runID }
    }

    /// The row for a PR: the run's own row when `runID` names a run that has it, else the newest run's row.
    nonisolated static func row(runID: String?, stripID: String, in sweeps: [ReviewSweep]) -> ReviewRow? {
        if let runID, let row = sweeps.first(where: { $0.id == runID })?.rows.first(where: { $0.stripID == stripID }) {
            return row
        }
        return sweeps.lazy.compactMap { $0.rows.first { $0.stripID == stripID } }.first
    }

    /// The newest `sweepLimit` runs.
    nonisolated static func newest(_ runs: [RunState]) -> [RunState] {
        Array(runs.sorted { $0.started > $1.started }.prefix(sweepLimit))
    }

    nonisolated static func sweeps(from runs: [RunState], posted: (_ runId: String, _ slug: String, _ n: Int) -> Date?) -> [ReviewSweep] {
        runs.map { run in ReviewSweep(run: run) { slug, n in posted(run.id, slug, n) } }
    }

    /// The runs grouped by the day they started, newest day first.
    var days: [DayRuns] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: runs) { calendar.startOfDay(for: $0.started) }
        return groups.keys.sorted(by: >).map { DayRuns(day: $0, runs: groups[$0] ?? []) }
    }

    /// "Today", "Yesterday", or "Mon 20 Oct".
    nonisolated static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "EEE d MMM"
        return format.string(from: day)
    }
}
