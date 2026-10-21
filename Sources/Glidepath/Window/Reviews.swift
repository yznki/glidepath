import SwiftUI
import AppKit

/// The Reviews section (v1.2 mockup 6-reviews): a 340 pt list of the reviews from the last 50 sweeps, beside the
/// selected review. Review text comes from `ReviewText` and is drawn as plain text only.
struct ReviewsView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ReviewsModel()

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 340)
                .frame(maxHeight: .infinity, alignment: .top)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(WinTheme.line).frame(width: 1)
                }
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { model.load(store) }
        .onReceive(store.$snap) { _ in model.load(store) }
    }

    // MARK: List

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reviews")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(WinTheme.text)
                .frame(height: 32, alignment: .leading)
                .padding(.horizontal, WinMetrics.s20)
            WinSegmented(segments: ReviewFilter.allCases.map { segment($0) }, selected: model.filter) { model.filter = $0 }
                .padding(.top, WinMetrics.s16)
                .padding(.horizontal, WinMetrics.s20)
            WinScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visible) { sweep in
                        Text(sweep.title)
                            .font(.system(size: 12))
                            .foregroundStyle(WinTheme.faint)
                            .padding(.horizontal, WinMetrics.s20)
                            .padding(.top, WinMetrics.s16)
                            .padding(.bottom, WinMetrics.s4)
                        ForEach(sweep.rows) { row in
                            listRow(row)
                        }
                    }
                    if model.visible.isEmpty {
                        Text("No reviews to show.")
                            .font(.system(size: 13))
                            .foregroundStyle(WinTheme.muted)
                            .padding(WinMetrics.s20)
                    }
                }
                .padding(.bottom, WinMetrics.canvasBottom)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.top, WinMetrics.titlebarZone)
    }

    private func segment(_ filter: ReviewFilter) -> WinSegmented<ReviewFilter>.Segment {
        let title = filter == .all ? filter.title : "\(filter.title) \(model.count(filter))"
        return WinSegmented<ReviewFilter>.Segment(value: filter, title: title)
    }

    /// A 56 pt row: title (13 medium) over meta (12 faint), the status in its fixed column. The selected row takes
    /// the active fill.
    private func listRow(_ row: ReviewRow) -> some View {
        let on = model.selected?.id == row.id
        return Button {
            model.selectedID = row.id
        } label: {
            HStack(spacing: WinMetrics.s12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(row.title ?? "#\(row.number)")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WinTheme.text)
                        .lineLimit(1)
                        .frame(height: 20, alignment: .leading)
                    Text(row.metaText)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .lineLimit(1)
                        .frame(height: 16, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let kind = row.status {
                    WinStatus(kind: kind)
                }
            }
            .padding(.horizontal, WinMetrics.s20)
            .frame(height: 56)
            .background(on ? WinTheme.active : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let row = model.selected {
            ReviewDetail(row: row, store: store)
        } else {
            Text("No review selected.")
                .font(.system(size: 13))
                .foregroundStyle(WinTheme.faint)
                .padding(.top, WinMetrics.titlebarZone)
                .padding(.leading, WinMetrics.canvasLeft)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// The review on the right: crumb, title, meta, the verdict bar with its actions, the review body, the inline
/// comments as cards, and the footer.
struct ReviewDetail: View {
    let row: ReviewRow
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    private var p: Palette { Palette(scheme) }

    /// The row as the store's post, discard and review actions see it.
    private var strip: Strip {
        Strip(repo: row.repo, number: row.number, author: row.author, title: row.title, reason: row.reason,
              stage: 4, active: false, verdict: row.verdict, tokens: row.tokens, draft: row.draft,
              skipReason: row.skipReason, changedLines: row.changedLines)
    }

    var body: some View {
        VStack(spacing: 0) {
            WinScroll {
                content
            }
            .frame(maxHeight: .infinity)
            footer
                .padding(.horizontal, WinMetrics.canvasLeft)
                .padding(.top, WinMetrics.s16)
                .padding(.bottom, WinMetrics.canvasBottom)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
                Text(crumb)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                Text(row.title ?? "#\(row.number)")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(WinTheme.text)
                    .padding(.top, WinMetrics.s4)
                if !metaParts.isEmpty {
                    HStack(spacing: WinMetrics.s16) {
                        ForEach(metaParts, id: \.self) { part in
                            Text(part)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.muted)
                    .monospacedDigit()
                    .padding(.top, WinMetrics.s8)
                }
                verdictBar
                    .padding(.top, WinMetrics.s16)
                if let error = store.draftErrors[row.stripID] {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(p.error)
                        .padding(.top, WinMetrics.s8)
                }
                bodyView
                    .padding(.top, WinMetrics.s20)
                ForEach(Array((row.text?.comments ?? []).enumerated()), id: \.offset) { _, comment in
                    commentCard(comment)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.horizontal, WinMetrics.canvasLeft)
    }

    private var crumb: String {
        var parts = ["\(row.repo) · #\(row.number)"]
        if let author = row.author { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    /// Head, size and flagged paths, each only when it is known.
    private var metaParts: [String] {
        var parts: [String] = []
        if let head = row.head { parts.append("head \(String(head.prefix(7)))") }
        if let lines = row.changedLines { parts.append("\(lines.formatted()) lines changed") }
        if row.flagged { parts.append("Touches \(flaggedPaths)") }
        return parts
    }

    /// The repo's flagged paths, as configured (`infra/, .github/workflows/`).
    private var flaggedPaths: String {
        let paths = store.snap.config?.repos.first { $0.slug == row.repo }?.flagPaths ?? []
        return paths.isEmpty ? "flagged paths" : paths.joined(separator: ", ")
    }

    // MARK: Verdict bar

    private var verdictWord: String {
        if row.tooLarge { return "Too large" }
        if row.verdict == .skipped { return "Skipped" }
        if row.text?.event == "COMMENT" { return "Comment" }
        switch row.verdict {
        case .changes: return "Changes requested"
        case .approve: return "Approved"
        default: return "Review"
        }
    }

    /// Draft or posted, when the text says so. Legacy rows have no record, so they say nothing.
    private var stateWord: String? {
        if row.draft { return "Draft, not posted" }
        if row.postedAt != nil { return "Posted" }
        return nil
    }

    private var isCommentOnly: Bool { row.text?.event == "COMMENT" }

    private var barFill: Color {
        if row.tooLarge || row.verdict == .skipped || isCommentOnly { return WinTheme.surface }
        return row.verdict == .changes ? WinTheme.amberBg : WinTheme.greenBg
    }

    private var barInk: Color {
        if row.tooLarge || row.verdict == .skipped || isCommentOnly { return WinTheme.text }
        return row.verdict == .changes ? WinTheme.amberInk : WinTheme.green
    }

    private var verdictBar: some View {
        HStack(spacing: WinMetrics.s12) {
            Text(verdictWord)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(barInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            if let stateWord {
                Text(stateWord)
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }
            Spacer(minLength: WinMetrics.s8)
            barActions
        }
        .padding(.leading, WinMetrics.s16)
        .padding(.trailing, WinMetrics.s12)
        .frame(height: 56)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(barFill))
    }

    @ViewBuilder
    private var barActions: some View {
        if row.tooLarge {
            WinButton(title: "Review anyway", style: .outline, small: true) { confirmAndReview() }
                .disabled(store.snap.running)
        } else if row.draft {
            if let busy = store.draftBusy[row.stripID] {
                Text(busy == .posting ? "Posting…" : "Discarding…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WinTheme.blue)
            } else {
                HStack(spacing: WinMetrics.s8) {
                    WinButton(title: "Discard", style: .outline, small: true) { store.discardDraft(strip) }
                    WinButton(title: "Post review", style: .primary, small: true) { confirmAndPost() }
                }
                .fixedSize(horizontal: true, vertical: false)
                .disabled(store.snap.running)
            }
        } else if let postedAt = row.postedAt {
            Text("Posted \(HeaderCopy.clock(postedAt))")
                .font(.system(size: 13))
                .foregroundStyle(WinTheme.muted)
        }
    }

    // MARK: Body and comments

    /// The review body as plain paragraphs, split on blank lines. Without the text, the reason it is missing.
    @ViewBuilder
    private var bodyView: some View {
        if row.tooLarge {
            note("Too large: \((row.changedLines ?? 0).formatted()) lines, limit \(store.snap.maxChangedLines)")
        } else if let text = row.text {
            // Paragraphs are 8 apart (13/20 text, as the mockup's p + p).
            VStack(alignment: .leading, spacing: WinMetrics.s8) {
                ForEach(Array(Self.paragraphs(text.body).enumerated()), id: \.offset) { _, paragraph in
                    Text(verbatim: paragraph)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .foregroundStyle(WinTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 600, alignment: .leading)
                }
            }
        } else if row.verdict == .skipped {
            note(row.reason ?? "Skipped")
        } else {
            note("Review text not recorded (before 1.2)", faint: true)
        }
    }

    private func note(_ text: String, faint: Bool = false) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(faint ? WinTheme.faint : WinTheme.muted)
            .frame(maxWidth: 600, alignment: .leading)
    }

    /// One inline comment: its place in mono blue, then the text.
    private func commentCard(_ comment: PayloadComment) -> some View {
        VStack(alignment: .leading, spacing: WinMetrics.s4) {
            Text(verbatim: "\(comment.path):\(comment.line)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(WinTheme.blue)
            Text(verbatim: comment.body)
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(WinTheme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, WinMetrics.s12)
        .padding(.horizontal, WinMetrics.s16)
        .frame(maxWidth: 600, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(WinTheme.surface))
        .padding(.top, WinMetrics.s12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: WinMetrics.s16) {
            if let duration = row.duration {
                Text("Reviewed in \(Self.duration(duration))")
            }
            if row.tokens > 0 {
                Text("\(compactTokens(row.tokens)) tokens")
            }
            Spacer(minLength: 0)
            if RepoConfig.isValidSlug(row.repo) {
                WinButton(title: "Open on GitHub", style: .link) { openOnGitHub() }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(WinTheme.faint)
        .monospacedDigit()
    }

    /// Opens only the PR's own github.com page: the slug is validated and the number is an Int.
    private func openOnGitHub() {
        guard let url = URL(string: "https://github.com/\(row.repo)/pull/\(row.number)") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Confirmations (the same alerts as the popover)

    private func confirmAndPost() {
        let preview = store.draftPreview(strip)
        let alert = NSAlert()
        alert.messageText = "Post the review on \(row.repo) #\(row.number)?"
        alert.informativeText = preview.verdict + "\n\n" + preview.body
        alert.addButton(withTitle: "Post")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.postDraft(strip)
    }

    private func confirmAndReview() {
        let alert = NSAlert()
        alert.messageText = "Review #\(row.number) anyway?"
        alert.informativeText = store.reviewWarning(strip)
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.reviewPR(strip)
    }

    // MARK: Text helpers

    /// Blocks of text separated by one or more blank lines. Lines inside a block are kept.
    static func paragraphs(_ text: String) -> [String] {
        var out: [String] = []
        var current: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !current.isEmpty { out.append(current.joined(separator: "\n")) }
                current = []
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { out.append(current.joined(separator: "\n")) }
        return out
    }

    /// "3 min 12 s", or "42 s" under a minute.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let minutes = total / 60
        let rest = total % 60
        return minutes > 0 ? "\(minutes) min \(rest) s" : "\(rest) s"
    }
}

/// Which rows the list shows. The counts come from the loaded sweeps.
enum ReviewFilter: String, CaseIterable, Hashable {
    case all, changes, drafts, skipped

    var title: String {
        switch self {
        case .all: return "All"
        case .changes: return "Changes"
        case .drafts: return "Drafts"
        case .skipped: return "Skipped"
        }
    }

    func includes(_ row: ReviewRow) -> Bool {
        switch self {
        case .all: return true
        case .changes: return row.verdict == .changes
        case .drafts: return row.draft
        case .skipped: return row.verdict == .skipped
        }
    }
}

/// One PR's result in one sweep: a verdict, a held draft, or a skip. Carried-over rows are left out, since their
/// sweep is listed where they were decided.
struct ReviewRow: Identifiable {
    private static let isoFormatter = ISO8601DateFormatter()

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
    /// The sweep's length, from its start to its finish. nil while it runs.
    let duration: TimeInterval?
    /// The text as it was sent or held. nil for reviews from before 1.2.
    let text: ReviewTextRecord?

    var id: String { "\(runId)|\(repo)#\(number)" }
    /// The key the store uses for a PR's draft actions.
    var stripID: String { "\(repo)#\(number)" }
    var tooLarge: Bool { skipReason == "size" }

    var postedAt: Date? {
        text?.posted.flatMap { Self.isoFormatter.date(from: $0) }
    }

    var status: WinStatus.Kind? {
        if tooLarge { return .tooLarge }
        switch verdict {
        case .changes: return .changes
        case .approve: return .approved
        case .skipped: return .skipped
        case nil: return nil
        }
    }

    /// "repo #n · author · draft", or "posted", or the size or skip reason.
    var metaText: String {
        var parts = ["\(repo) #\(number)"]
        if let author { parts.append(author) }
        if draft {
            parts.append("draft")
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

/// One sweep (or one review run), with its rows. The title is "Today, 1:00 PM sweep".
struct ReviewSweep: Identifiable {
    let id: String
    let started: Date
    let isReview: Bool
    let duration: TimeInterval?
    var rows: [ReviewRow]

    /// `text` looks up the review text for a PR in this run: the text store in the app, the fixture in snapshots.
    init(run: RunState, text: (_ slug: String, _ n: Int) -> ReviewTextRecord?) {
        let length = run.finished.map { $0.timeIntervalSince(run.started) }
        id = run.id
        started = run.started
        isReview = run.kind == "review"
        duration = length
        rows = run.repos.flatMap { repo in
            repo.prs.compactMap { pr -> ReviewRow? in
                guard pr.carriedFrom == nil, pr.verdict != nil || pr.draft == true || pr.skipReason != nil else {
                    return nil
                }
                return ReviewRow(
                    runId: run.id, repo: repo.slug, number: pr.n, author: pr.author, title: pr.title,
                    reason: pr.reason, verdict: pr.verdict, draft: pr.draft == true, skipReason: pr.skipReason,
                    changedLines: pr.changedLines, head: pr.head, flagged: pr.flagged == true, tokens: pr.tokens,
                    duration: length,
                    text: text(repo.slug, pr.n))
            }
        }
    }

    init(id: String, started: Date, isReview: Bool, duration: TimeInterval?, rows: [ReviewRow]) {
        self.id = id
        self.started = started
        self.isReview = isReview
        self.duration = duration
        self.rows = rows
    }

    var title: String {
        let calendar = Calendar.current
        let day: String
        if calendar.isDateInToday(started) {
            day = "Today"
        } else if calendar.isDateInYesterday(started) {
            day = "Yesterday"
        } else {
            day = started.formatted(.dateTime.month(.abbreviated).day())
        }
        return "\(day), \(HeaderCopy.clock(started)) \(isReview ? "review" : "sweep")"
    }

    func filtered(by filter: ReviewFilter) -> ReviewSweep {
        ReviewSweep(id: id, started: started, isReview: isReview, duration: duration,
                    rows: rows.filter { filter.includes($0) })
    }
}

/// Loads the last 50 sweeps from disk and holds the list's filter and selection.
@MainActor
final class ReviewsModel: ObservableObject {
    static let sweepLimit = 50

    @Published var filter: ReviewFilter = .all
    @Published var selectedID: String?
    @Published private(set) var sweeps: [ReviewSweep] = []

    /// Reads every run file and keeps the newest 50 sweeps.
    /// ponytail: decodes every run file on each state change; index the runs if the folder grows large.
    func load(_ store: Store) {
        let runs = store.allRuns().sorted { $0.started > $1.started }.prefix(Self.sweepLimit)
        sweeps = runs.map { run in
            ReviewSweep(run: run) { slug, n in store.reviewText(runId: run.id, slug: slug, n: n) }
        }
    }

    /// The sweeps with the filter applied. Sweeps left empty are dropped.
    var visible: [ReviewSweep] {
        sweeps.map { $0.filtered(by: filter) }.filter { !$0.rows.isEmpty }
    }

    func count(_ filter: ReviewFilter) -> Int {
        sweeps.reduce(0) { total, sweep in total + sweep.rows.filter { filter.includes($0) }.count }
    }

    /// The selected row, or the first visible row when the selection is filtered out.
    var selected: ReviewRow? {
        let rows = visible.flatMap(\.rows)
        return rows.first { $0.id == selectedID } ?? rows.first
    }
}
