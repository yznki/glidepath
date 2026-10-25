import SwiftUI
import AppKit

/// The Reviews section (prototype `#rv`): a header with the tally (Approved, Changes, Skipped; click filters), and a
/// grid of glass cards for the newest sweep's reviews. Hold to post a held draft, discard it, or tap a card for the full
/// review in a sheet. Review text comes from `ReviewText` and is drawn as plain text only.
struct ReviewsView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ReviewsModel()
    @AppStorage("signalColour") private var signalKey = "amber"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                WinScroll {
                    if model.grid.isEmpty {
                        Text("No reviews to show.")
                            .font(.system(size: 13))
                            .foregroundStyle(Gotham.mute)
                            .padding(.top, WinMetrics.s8)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 18, alignment: .top)], spacing: 18) {
                            ForEach(model.grid) { row in
                                ReviewCard(row: row, store: store, highlighted: model.highlight == row.stripID) {
                                    model.highlight = row.stripID
                                    model.opened = row
                                }
                                .id(row.id)
                            }
                        }
                    }
                }
                .onChange(of: model.highlight) { _, _ in scroll(proxy) }
                .onChange(of: model.sweeps.count) { _, _ in scroll(proxy) }
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
        .onReceive(WindowRouter.shared.$pending.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeFilter()
        }
        .onReceive(WindowRouter.shared.$reviewFocus.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeFocus()
        }
        // The open card's draft flag can change without its id changing (a post or discard reloads the sweeps).
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

    // MARK: Header

    /// The title, the tally and a round run button. The tally's numerals filter the grid; a second click clears it.
    private var header: some View {
        HStack(alignment: .center, spacing: WinMetrics.s8) {
            Text("Reviews")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Gotham.fg)
            Spacer(minLength: WinMetrics.s8)
            tally(.approved, count: model.count(.approved), colour: Gotham.approve, title: "Approved")
            tally(.changes, count: model.count(.changes), colour: Gotham.signal(signalKey), title: "Changes")
            tally(.skipped, count: model.count(.skipped), colour: Gotham.skipped, title: "Skipped")
            Button {
                store.runNow()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.fg)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Gotham.row))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(store.snap.running || store.snap.dryRunning || !store.snap.jobInstalled)
            .padding(.leading, WinMetrics.s8)
        }
        .padding(.bottom, WinMetrics.s16)
    }

    private func tally(_ filter: ReviewFilter, count: Int, colour: Color, title: String) -> some View {
        let on = model.filter == filter
        return Button {
            model.filter = on ? .all : filter
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(count)")
                    .font(.system(size: 26, weight: .ultraLight))
                    .monospacedDigit()
                    .foregroundStyle(colour)
                capLabel(title)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(on ? Gotham.row : Color.clear))
            .opacity(model.filter == .all || on ? 1 : 0.25)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let id = model.highlight, let row = model.grid.first(where: { $0.stripID == id }) else { return }
        proxy.scrollTo(row.id)
    }

    /// Opens the review a Now row asked for: its card is highlighted, and the grid scrolls to it.
    private func takeFocus() {
        guard let id = WindowRouter.shared.reviewFocus else { return }
        WindowRouter.shared.reviewFocus = nil
        model.focus(id)
    }

    /// The filter shortcuts (View menu) set the filter. Other actions belong to the sheet.
    private func takeFilter() {
        let filters: [ShortcutAction: ReviewFilter] = [.filterAll: .all, .filterChanges: .changes,
                                                      .filterDrafts: .waiting, .filterSkipped: .skipped]
        if let action = WindowRouter.shared.take(Set(filters.keys)), let filter = filters[action] {
            model.filter = filter
        }
    }
}

/// One review as a glass card (prototype `cardEl` flat): avatar, author, verdict word; the title, PR and repo, the
/// reason; and the card's one action. A held draft holds to post; a finished review links to GitHub. The card tilts
/// toward the pointer.
struct ReviewCard: View {
    let row: ReviewRow
    @ObservedObject var store: Store
    var highlighted = false
    let onOpen: () -> Void

    @StateObject private var tilt = TiltModel()
    @AppStorage("signalColour") private var signalKey = "amber"
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var strip: Strip { row.strip }
    private var signal: Color { Gotham.signal(signalKey) }
    private var verdictColour: Color {
        switch row.verdict {
        case .changes?: return signal
        case .approve?: return Gotham.approve
        default: return Gotham.skipped
        }
    }
    private var light: VerdictLight {
        if row.draft { return .changes }
        switch row.verdict {
        case .changes?: return .changes
        case .approve?: return .approve
        default: return .skipped
        }
    }
    private var verdictWord: String {
        if row.draft { return "Waiting" }
        switch row.verdict {
        case .changes?: return "Changes"
        case .approve?: return "Approved"
        case .skipped?: return "Skipped"
        case nil: return "No result"
        }
    }

    var body: some View {
        let still = Motion.reduced(reduceMotion)
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        AvatarView(login: row.author ?? "pr", size: 34)
                        Text(row.author ?? "#\(row.number)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Gotham.fg)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        HStack(spacing: 7) {
                            Circle().fill(verdictColour).frame(width: 6, height: 6)
                            capLabel(verdictWord, row.verdict == .skipped && !row.draft ? Gotham.mute : verdictColour)
                        }
                    }
                    Text(row.title ?? "#\(row.number)")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(Gotham.fg)
                        .lineLimit(2)
                        .padding(.top, 4)
                    Text(row.metaText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Gotham.mute)
                        .lineLimit(1)
                    if let reason = row.reason, row.verdict != .skipped {
                        Text(reason)
                            .font(.system(size: 13))
                            .lineSpacing(2)
                            .foregroundStyle(Gotham.fg.opacity(0.8))
                            .lineLimit(3)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                Spacer(minLength: 10)
                actions
            }
            .padding(18)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .glassCard(radius: 20, verdict: light, held: row.draft)
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(Gotham.fg.opacity(0.6), lineWidth: 1.5)
                }
            }
            .offset(y: tilt.hover && !still ? -3 : 0)
            .rotation3DEffect(.degrees(still || !tilt.hover ? 0 : (0.5 - tilt.py) * 7), axis: (x: 1, y: 0, z: 0))
            .rotation3DEffect(.degrees(still || !tilt.hover ? 0 : (tilt.px - 0.5) * 9), axis: (x: 0, y: 1, z: 0))
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    tilt.px = min(max(point.x / max(geo.size.width, 1), 0), 1)
                    tilt.py = min(max(point.y / max(geo.size.height, 1), 0), 1)
                    tilt.hover = true
                case .ended:
                    tilt.hover = false
                }
            }
            .animation(Motion.release, value: tilt.hover)
        }
        .frame(height: 250)
    }

    @ViewBuilder
    private var actions: some View {
        if row.draft {
            if let busy = store.draftBusy[row.stripID] {
                Text(busy == .posting ? "Posting…" : "Discarding…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gotham.mute)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                HStack(spacing: 8) {
                    HoldButton(title: "Hold to post", doneTitle: "Posting…", tint: verdictColour) {
                        store.postDraft(strip)
                    }
                    .id(row.id)
                    .disabled(store.snap.running)
                    Button("Discard") { Confirm.discard(strip, store: store) }
                        .buttonStyle(.plain)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Gotham.mute)
                        .frame(height: 44)
                        .padding(.horizontal, 10)
                        .disabled(store.snap.running)
                }
            }
        } else if row.verdict != nil && !row.tooLarge {
            Button {
                if let url = URL(string: "https://github.com/\(row.repo)/pull/\(row.number)") { NSWorkspace.shared.open(url) }
            } label: {
                Text("Open on GitHub")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Gotham.fg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Capsule().fill(Gotham.row))
                    .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(height: 44)
        }
    }
}

/// Pointer position over a card, in unit coordinates, and whether it is over the card.
final class TiltModel: ObservableObject {
    @Published var px: CGFloat = 0.5
    @Published var py: CGFloat = 0.5
    @Published var hover = false
}

/// The full review for a tapped card, as a sheet. Its body is `ReviewDetail`; Done closes it.
struct ReviewSheet: View {
    let row: ReviewRow
    let text: ReviewTextRecord?
    @ObservedObject var store: Store
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Done", action: onClose)
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
            ReviewDetail(row: row, text: text, store: store)
        }
        .frame(width: 720, height: 620)
        .background(Gotham.void)
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
                    .foregroundStyle(Gotham.mute)
                Text(row.title ?? "#\(row.number)")
                    .font(.system(size: 24, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Gotham.fg)
                    .padding(.top, WinMetrics.s4)
                if !metaParts.isEmpty {
                    HStack(spacing: WinMetrics.s16) {
                        ForEach(metaParts, id: \.self) { part in
                            Text(part)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
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
        case nil: return "No result"
        default: return "Review"
        }
    }

    /// Draft or posted, when the text says so. Legacy rows have no record, so they say nothing.
    private var stateWord: String? {
        if row.draft { return "Waiting for you" }
        if row.postedAt != nil { return "Posted" }
        return nil
    }

    private var isCommentOnly: Bool { text?.event == "COMMENT" }

    private var barFill: Color {
        if row.tooLarge || row.verdict == nil || row.verdict == .skipped || isCommentOnly { return WinTheme.surface }
        return row.verdict == .changes ? WinTheme.amberBg : WinTheme.greenBg
    }

    private var barInk: Color {
        if row.tooLarge || row.verdict == nil || row.verdict == .skipped || isCommentOnly { return Gotham.fg }
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
                    .foregroundStyle(Gotham.mute)
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
                .foregroundStyle(Gotham.mute)
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
                        .foregroundStyle(Gotham.mute)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 600, alignment: .leading)
                }
            }
        } else if row.verdict == .skipped {
            // The verdict bar already says why it was skipped.
            EmptyView()
        } else if row.verdict == nil {
            note("The review session ended without a verdict. See the log.")
        } else {
            note("Review text not recorded (before 1.2)", faint: true)
        }
    }

    private func note(_ text: String, faint: Bool = false) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13))
            .lineSpacing(4)
            .foregroundStyle(faint ? Gotham.mute : Gotham.mute)
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
                .foregroundStyle(Gotham.fg)
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
        .foregroundStyle(Gotham.mute)
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
    case all, changes, waiting, skipped, approved

    var title: String {
        switch self {
        case .all: return "All"
        case .changes: return "Changes"
        case .waiting: return "Waiting"
        case .skipped: return "Skipped"
        case .approved: return "Approved"
        }
    }

    func includes(_ row: ReviewRow) -> Bool {
        switch self {
        // Skipped PRs are listed under the Skipped segment, except too-large ones, which offer Review anyway.
        case .all: return row.verdict != .skipped || row.tooLarge
        case .changes: return row.verdict == .changes
        case .waiting: return row.draft
        case .skipped: return row.verdict == .skipped
        case .approved: return row.verdict == .approve && !row.draft
        }
    }
}

/// One PR's result in one sweep: a verdict, a held draft, a skip, or No result (the run finished without a verdict).
/// Carried-over rows are left out, since their sweep is listed where they were decided.
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
    /// The review the sheet shows. The Review commands act on it.
    @Published var opened: ReviewRow?
    /// The selected card: a PR's `Strip.id`, set by a tap or by a Now row.
    @Published var highlight: String?
    @Published private(set) var sweeps: [ReviewSweep] = []
    /// A Now row's PR, asked for before the sweeps finished loading. Opened when they arrive.
    private var pendingOpen: String?
    private var loadTask: Task<Void, Never>?

    /// Keeps the newest 50 sweeps. Live, the run files are read off the main actor, after a 300 ms pause: a burst of
    /// store changes costs one read, and a read still waiting when the next change lands is cancelled. Fixtures load at
    /// once, since snapshot rendering reads them synchronously.
    /// ponytail: decodes every run file on each load; index the runs if the folder grows large.
    func load(_ store: Store) {
        loadTask?.cancel()
        if store.isFixture {
            show(Self.sweeps(from: store.allRuns()) { runId, slug, n in
                store.reviewText(runId: runId, slug: slug, n: n)?.postedDate
            })
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
            self?.show(loaded)
        }
    }

    private func show(_ loaded: [ReviewSweep]) {
        sweeps = loaded
        if let id = pendingOpen {
            pendingOpen = nil
            if let row = Self.row(stripID: id, in: loaded) { opened = row }
        }
    }

    /// Selects a PR's card and opens its review, as a Now row's tap asks. Before the sweeps load, the open waits for them.
    func focus(_ stripID: String) {
        highlight = stripID
        if sweeps.isEmpty {
            pendingOpen = stripID
        } else if let row = Self.row(stripID: stripID, in: sweeps) {
            opened = row
        }
    }

    /// The row for a PR, from the newest sweep that has one. Rows are matched by `stripID` (repo and number), so a
    /// carried PR finds the sweep that decided it.
    nonisolated static func row(stripID: String, in sweeps: [ReviewSweep]) -> ReviewRow? {
        for sweep in sweeps {
            if let row = sweep.rows.first(where: { $0.stripID == stripID }) { return row }
        }
        return nil
    }

    /// The newest sweep with at least one row. A run whose rows were all carried over has none, so it is skipped.
    nonisolated static func current(in sweeps: [ReviewSweep]) -> ReviewSweep? {
        sweeps.first { !$0.rows.isEmpty }
    }

    /// The newest `sweepLimit` runs as sweeps.
    nonisolated static func sweeps(from runs: [RunState], posted: (_ runId: String, _ slug: String, _ n: Int) -> Date?) -> [ReviewSweep] {
        runs.sorted { $0.started > $1.started }.prefix(sweepLimit).map { run in
            ReviewSweep(run: run) { slug, n in posted(run.id, slug, n) }
        }
    }

    /// The current sweep's reviews, as the grid shows them. Under All, every review (skips included).
    var grid: [ReviewRow] {
        (Self.current(in: sweeps)?.rows ?? []).filter { filter == .all || filter.includes($0) }
    }

    /// How many of the current sweep's reviews a tally numeral counts.
    func count(_ filter: ReviewFilter) -> Int {
        (Self.current(in: sweeps)?.rows ?? []).filter(filter.includes).count
    }
}
