import SwiftUI
import AppKit

/// The Reviews section (v1.2 mockup 6-reviews): a 340 pt list of the reviews from the last 50 sweeps, beside the
/// selected review. Review text comes from `ReviewText` and is drawn as plain text only.
/// Where keyboard focus sits in Reviews: the list (arrows move the selection) or the detail (Return moves here).
enum ReviewsFocus: Hashable { case list, detail }

struct ReviewsView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ReviewsModel()
    @FocusState private var focus: ReviewsFocus?

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
                .focusable()
                .focusEffectDisabled()
                .focused($focus, equals: .detail)
        }
        .onAppear {
            model.load(store)
            focus = .list
        }
        .onReceive(store.$snap) { _ in model.load(store) }
        .onReceive(WindowRouter.shared.$pending.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeFilter()
        }
        // The selected row's draft flag can change without its id changing (a post or discard reloads the sweeps).
        .onChange(of: model.selected?.id) { _ in ShortcutContext.shared.setReview(model.selected) }
        .onChange(of: model.selected?.draft) { _ in ShortcutContext.shared.setReview(model.selected) }
        .onReceive(model.$sweeps) { _ in ShortcutContext.shared.setReview(model.selected) }
        .onDisappear { ShortcutContext.shared.setReview(nil) }
        .onKeyPress(phases: .down) { handleKey($0) }
    }

    // MARK: Keys

    /// Arrows, Home and End move the selection; Return moves focus to the detail; Esc clears the filter; a letter
    /// jumps to the first title that starts with the letters typed. Nothing fires while a text field has focus.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !TextFocus.isEditing else { return .ignored }
        let mods = ShortcutModifiers(press.modifiers)
        if focus == .detail {
            // Space pages the review body down, as it does in a document.
            guard press.key == .space, mods.isEmpty else { return .ignored }
            ScrollPager.pageDown()
            return .handled
        }
        // With no focus (after a sheet, or a click on the filter), the list takes the keys.
        if focus == nil { focus = .list }
        guard focus == .list else { return .ignored }
        if press.key == .return, mods.isEmpty {
            if case .skipped(let sweepID, _, _)? = model.selectedEntry {
                model.toggleSkipped(sweepID)
                return .handled
            }
            focus = .detail
            return .handled
        }
        if press.key == .escape, mods.isEmpty {
            guard model.filter != .all else { return .ignored }
            model.filter = .all
            return .handled
        }
        if let key = ListKey(press.key), let move = ListNav.move(key, mods) {
            step(move)
            return .handled
        }
        if mods.subtracting(.shift).isEmpty, press.characters.count == 1, let ch = press.characters.first,
           ch.isLetter || ch.isNumber {
            typeSelect(String(ch))
            return .handled
        }
        return .ignored
    }


    private func step(_ move: ListMove) {
        let entries = model.visible.flatMap(\.entries)
        let current = entries.firstIndex { $0.id == model.selectedEntry?.id }
        guard let i = ListNav.move(move, from: current, count: entries.count, groupStarts: model.groupStarts) else { return }
        model.selectedID = entries[i].id
    }

    /// Letters typed within a second make one search string. The first title that starts with it is selected.
    private func typeSelect(_ letter: String) {
        let now = Date()
        model.typed = (now.timeIntervalSince(model.typedAt) < 1 ? model.typed : "") + letter
        model.typedAt = now
        let entries = model.visible.flatMap(\.entries)
        // The summary line has no title, so no letters select it.
        let titles = entries.map(\.title)
        let current = entries.firstIndex { $0.id == model.selectedEntry?.id }
        if let i = ListNav.typeSelect(model.typed, titles: titles, from: current) {
            model.selectedID = entries[i].id
        }
    }

    /// The filter shortcuts (View menu) set the filter. Other actions belong to the detail.
    private func takeFilter() {
        let filters: [ShortcutAction: ReviewFilter] = [.filterAll: .all, .filterChanges: .changes,
                                                      .filterDrafts: .drafts, .filterSkipped: .skipped]
        let actions = Set(filters.keys)
        if let action = WindowRouter.shared.take(actions), let filter = filters[action] {
            model.filter = filter
        }
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
            ScrollViewReader { proxy in
            WinScroll {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.visible) { sweep in
                        Text(sweep.title)
                            .font(.system(size: 12))
                            .foregroundStyle(WinTheme.faint)
                            .padding(.horizontal, WinMetrics.s20)
                            .padding(.top, WinMetrics.s16)
                            .padding(.bottom, WinMetrics.s4)
                        ForEach(sweep.entries) { entry in
                            switch entry {
                            case .row(let row): listRow(row)
                            case .skipped(let sweepID, let text, let expanded): skippedRow(sweepID, text, expanded)
                            }
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
            .onChange(of: model.selectedID) { id in
                if let id { proxy.scrollTo(id) }
            }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: .list)
        }
        .padding(.top, WinMetrics.titlebarZone)
    }

    /// The selected line's fill: full `active` while the list has focus, half while it does not (Mail and Finder).
    private var selectionFill: Color {
        focus == .list ? WinTheme.active : WinTheme.active.opacity(0.5)
    }

    /// The muted line that folds a sweep's skipped PRs (All filter). A click or Return expands or collapses them in place.
    private func skippedRow(_ sweepID: String, _ text: String, _ expanded: Bool) -> some View {
        let entryID = ReviewEntry.skippedID(sweepID)
        let on = model.selectedEntry?.id == entryID
        return Button {
            model.selectedID = entryID
            model.toggleSkipped(sweepID)
            focus = .list
        } label: {
            HStack(spacing: WinMetrics.s8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.muted)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WinTheme.faint)
            }
            .padding(.horizontal, WinMetrics.s20)
            .padding(.vertical, WinMetrics.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? selectionFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .id(entryID)
    }

    private func segment(_ filter: ReviewFilter) -> WinSegmented<ReviewFilter>.Segment {
        let title = filter == .all ? filter.title : "\(filter.title) \(model.count(filter))"
        return WinSegmented<ReviewFilter>.Segment(value: filter, title: title)
    }

    /// A 56 pt row: title (13 medium) over meta (12 faint), the status in its fixed column. The selected row takes
    /// the active fill.
    private func listRow(_ row: ReviewRow) -> some View {
        let on = model.selectedEntry?.id == row.id
        return Button {
            model.selectedID = row.id
            focus = .list
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
            .background(on ? selectionFill : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The list takes the keys, so the rows are not separate Tab stops.
        .focusable(false)
        .id(row.id)
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let row = model.selected {
            // The text is read for the selected row only; the list keeps just the posted time.
            ReviewDetail(row: row, text: store.reviewText(runId: row.runId, slug: row.repo, n: row.number), store: store)
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
    /// What the review said, read for this row. Nil for reviews from before 1.2.
    let text: ReviewTextRecord?
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    private var p: Palette { Palette(scheme) }

    /// The row as the store's post, discard and review actions see it.
    private var strip: Strip { row.strip }

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
        .onReceive(WindowRouter.shared.$pending.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeReviewAction()
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
                ForEach(Array((text?.comments ?? []).enumerated()), id: \.offset) { _, comment in
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
        if row.verdict == .skipped { return row.reason.map { "Skipped · \($0)" } ?? "Skipped" }
        if text?.event == "COMMENT" { return "Comment" }
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

    private var isCommentOnly: Bool { text?.event == "COMMENT" }

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
            // The verdict keeps its full width on one line; the state word gives way first when the bar is narrow.
            Text(verdictWord)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(barInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            if let stateWord {
                Text(stateWord)
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                    .lineLimit(1)
                    .layoutPriority(0)
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
                    WinButton(title: "Discard", style: .outline, small: true) { Confirm.discard(strip, store: store) }
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
        } else if let text {
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
            // The verdict bar already says why it was skipped.
            EmptyView()
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
            // A skipped PR was never reviewed, so it has no duration or tokens.
            if row.verdict != .skipped {
                if let duration = row.duration {
                    Text("Reviewed in \(Self.duration(duration))")
                }
                if row.tokens > 0 {
                    Text("\(compactTokens(row.tokens)) tokens")
                }
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

    /// The review menu's actions, for the selected row. Each is enabled only when it applies (see `ShortcutAvailability`).
    private func takeReviewAction() {
        let actions: Set<ShortcutAction> = [.postReview, .discardDraft, .reviewAnyway, .openOnGitHub, .copyLink,
                                            .copyReviewText]
        guard let action = WindowRouter.shared.take(actions) else { return }
        switch action {
        case .postReview:
            if row.draft, store.draftBusy[row.stripID] == nil, !store.snap.running { confirmAndPost() }
        case .discardDraft:
            if row.draft, !store.snap.running { Confirm.discard(strip, store: store) }
        case .reviewAnyway:
            if row.tooLarge, !store.snap.running { confirmAndReview() }
        case .openOnGitHub:
            openOnGitHub()
        case .copyLink:
            copy("https://github.com/\(row.repo)/pull/\(row.number)")
        case .copyReviewText:
            if let body = text?.body { copy(body) }
        default:
            break
        }
    }

    private func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
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
        // Skipped PRs are listed under the Skipped segment, except too-large ones, which offer Review anyway.
        case .all: return row.verdict != .skipped || row.tooLarge
        case .changes: return row.verdict == .changes
        case .drafts: return row.draft
        case .skipped: return row.verdict == .skipped
        }
    }
}

/// One PR's result in one sweep: a verdict, a held draft, or a skip. Carried-over rows are left out, since their
/// sweep is listed where they were decided.
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
    /// The sweep's length, from its start to its finish. nil while it runs.
    let duration: TimeInterval?
    /// When the review was posted, from its text record. nil while it is a draft, and for reviews from before 1.2.
    let postedAt: Date?

    var id: String { "\(runId)|\(repo)#\(number)" }
    /// The key the store uses for a PR's draft actions.
    var stripID: String { "\(repo)#\(number)" }
    var tooLarge: Bool { skipReason == "size" }
    /// A skip that the All filter folds into its sweep's summary line: every skip but a too-large one.
    var isFoldedSkip: Bool { verdict == .skipped && !tooLarge }
    /// The row as the store's post, discard and skip summary see it.
    var strip: Strip {
        Strip(repo: repo, number: number, author: author, title: title, reason: reason, stage: 4, active: false,
              verdict: verdict, tokens: tokens, draft: draft, skipReason: skipReason, changedLines: changedLines)
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

/// One line of the list: a PR's row, or a sweep's summary of its skipped PRs (All filter).
enum ReviewEntry: Identifiable {
    case row(ReviewRow)
    case skipped(sweepID: String, text: String, expanded: Bool)

    static func skippedID(_ sweepID: String) -> String { "skipped|\(sweepID)" }

    var id: String {
        switch self {
        case .row(let row): return row.id
        case .skipped(let sweepID, _, _): return Self.skippedID(sweepID)
        }
    }

    var row: ReviewRow? {
        if case .row(let row) = self { return row }
        return nil
    }

    /// The row's title for type-to-select. The summary line has none.
    var title: String {
        guard let row else { return "" }
        return row.title ?? "#\(row.number)"
    }
}

/// One sweep (or one review run), with its rows. The title is "Today, 1:00 PM sweep".
struct ReviewSweep: Identifiable {
    let id: String
    let started: Date
    let isReview: Bool
    let duration: TimeInterval?
    /// The rows shown, in sweep order.
    var rows: [ReviewRow]
    /// The skipped rows the All filter folds into the summary line. Empty under the other filters.
    var folded: [ReviewRow] = []
    /// Whether the folded rows are listed under the summary line.
    var expanded = false

    /// The sweep's lines: its rows, then the summary of its folded skips, then those skips when expanded.
    var entries: [ReviewEntry] {
        var out = rows.map(ReviewEntry.row)
        guard let text = OnboardingSummary.skippedLine(folded.map(\.strip)) else { return out }
        out.append(.skipped(sweepID: id, text: text, expanded: expanded))
        if expanded { out += folded.map(ReviewEntry.row) }
        return out
    }

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
                guard pr.carriedFrom == nil, pr.verdict != nil || pr.draft == true || pr.skipReason != nil else {
                    return nil
                }
                return ReviewRow(
                    runId: run.id, repo: repo.slug, number: pr.n, author: pr.author, title: pr.title,
                    reason: pr.reason, verdict: pr.verdict, draft: pr.draft == true, skipReason: pr.skipReason,
                    changedLines: pr.changedLines, head: pr.head, flagged: pr.flagged == true, tokens: pr.tokens,
                    duration: length,
                    postedAt: posted(repo.slug, pr.n))
            }
        }
    }

    init(id: String, started: Date, isReview: Bool, duration: TimeInterval?, rows: [ReviewRow],
         folded: [ReviewRow] = [], expanded: Bool = false) {
        self.id = id
        self.started = started
        self.isReview = isReview
        self.duration = duration
        self.rows = rows
        self.folded = folded
        self.expanded = expanded
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

    /// Under All, the skipped PRs (but the too-large ones) are folded into the summary. The other filters show their rows.
    static func split(_ rows: [ReviewRow], filter: ReviewFilter) -> (shown: [ReviewRow], folded: [ReviewRow]) {
        guard filter == .all else { return (rows.filter { filter.includes($0) }, []) }
        return (rows.filter { !$0.isFoldedSkip }, rows.filter(\.isFoldedSkip))
    }

    func filtered(by filter: ReviewFilter, expanded: Bool) -> ReviewSweep {
        let split = Self.split(rows, filter: filter)
        return ReviewSweep(id: id, started: started, isReview: isReview, duration: duration,
                           rows: split.shown, folded: split.folded, expanded: expanded)
    }
}

/// Loads the last 50 sweeps from disk and holds the list's filter and selection.
@MainActor
final class ReviewsModel: ObservableObject {
    nonisolated static let sweepLimit = 50

    @Published var filter: ReviewFilter = .all
    @Published var selectedID: String?
    /// The sweeps whose skipped summary is expanded.
    @Published private(set) var expanded: Set<String> = []
    @Published private(set) var sweeps: [ReviewSweep] = []
    private var loadTask: Task<Void, Never>?
    /// Type-to-select: the letters typed so far, and when the last one came.
    var typed = ""
    var typedAt = Date.distantPast

    /// The index of each visible sweep's first line, in the flat list. Group jumps (⌥↑ ⌥↓) move between these.
    var groupStarts: [Int] {
        var starts: [Int] = []
        var index = 0
        for sweep in visible {
            starts.append(index)
            index += sweep.entries.count
        }
        return starts
    }

    /// Expands or collapses one sweep's skipped summary.
    func toggleSkipped(_ sweepID: String) {
        if expanded.contains(sweepID) { expanded.remove(sweepID) } else { expanded.insert(sweepID) }
    }

    /// Keeps the newest 50 sweeps. Live, the run files are read off the main actor, after a 300 ms pause: a burst of
    /// store changes costs one read, and a read still waiting when the next change lands is cancelled. Fixtures load at
    /// once, since snapshot rendering reads them synchronously.
    /// ponytail: decodes every run file on each load; index the runs if the folder grows large.
    func load(_ store: Store) {
        loadTask?.cancel()
        if store.isFixture {
            sweeps = Self.sweeps(from: store.allRuns()) { runId, slug, n in
                store.reviewText(runId: runId, slug: slug, n: n)?.postedDate
            }
            return
        }
        let paths = store.paths
        loadTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let loaded = await Task.detached(priority: .utility) { () -> [ReviewSweep] in
                Self.sweeps(from: RunStore(paths: paths).loadAll()) { runId, slug, n in
                    ReviewText.read(paths, runId: runId, slug: slug, n: n)?.postedDate
                }
            }.value
            guard !Task.isCancelled else { return }
            self?.sweeps = loaded
        }
    }

    /// The newest `sweepLimit` runs as sweeps.
    nonisolated static func sweeps(from runs: [RunState], posted: (_ runId: String, _ slug: String, _ n: Int) -> Date?) -> [ReviewSweep] {
        runs.sorted { $0.started > $1.started }.prefix(sweepLimit).map { run in
            ReviewSweep(run: run) { slug, n in posted(run.id, slug, n) }
        }
    }

    /// The sweeps with the filter applied. Sweeps left with no lines are dropped.
    var visible: [ReviewSweep] {
        sweeps.map { $0.filtered(by: filter, expanded: expanded.contains($0.id)) }.filter { !$0.entries.isEmpty }
    }

    func count(_ filter: ReviewFilter) -> Int {
        sweeps.reduce(0) { total, sweep in total + sweep.rows.filter { filter.includes($0) }.count }
    }

    /// The selected line, or the first row when the selection is filtered out. Nil when the summary line is selected.
    var selectedEntry: ReviewEntry? {
        let entries = visible.flatMap(\.entries)
        if let selectedID, let hit = entries.first(where: { $0.id == selectedID }) { return hit }
        return entries.first { $0.row != nil }
    }

    /// The selected row. Nil while the selected line is a summary.
    var selected: ReviewRow? { selectedEntry?.row }
}
