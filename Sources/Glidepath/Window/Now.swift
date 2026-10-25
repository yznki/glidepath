import SwiftUI

/// The Now section: what needs you, and what the newest runs did. The header holds the status line and the Review menu
/// on one row. Held drafts and the newest run's too-large PRs come first, each with its action. With none and nothing
/// running, the section says nothing needs you. The three newest runs follow as run cards. A PR opens its flight recorder.
struct NowView: View {
    @ObservedObject var store: Store
    @AppStorage("signalColour") private var signalKey = "amber"
    @Environment(\.offscreenRender) private var offscreen
    /// The "Review a PR or author…" sheet's state. Owned here, as `ReposView` owns its `ReposModel`.
    @StateObject private var reviewModel = ReviewSheetModel()
    /// The runs and their reviews, loaded off the main thread. Its sheet opens a PR from this section.
    @StateObject private var history = ReviewsModel()

    private var snap: Snapshot { store.snap }
    private var running: Bool { snap.running }
    private var signal: Color { Gotham.signal(signalKey) }

    /// Held drafts: the PRs that wait on the user to post or discard them.
    private var held: [Strip] { store.strips.filter { $0.draft && $0.verdict != nil } }

    /// The newest run's own PRs skipped for size: each waits for Review anyway.
    private var tooLarge: [Strip] { store.strips.filter { $0.offersReview && $0.carriedFrom == nil } }

    /// Tend's held fixes and stuck PRs, the same items the Approach section lists.
    private var tendNeeds: [NeedsItem] { snap.approach?.needs ?? [] }

    private var needsCount: Int { held.count + tooLarge.count + tendNeeds.count }

    /// True when the newest run finished with no error and no stopped PR: then the all-clear line can promise that
    /// every open PR is reviewed.
    private var cleanFinish: Bool {
        guard let run = snap.run, run.finished != nil, let digest = newest else { return false }
        return digest.failed == nil && digest.stopped.isEmpty
    }

    private var newest: RunDigest? { snap.run.map { RunDigest(run: $0, running: running) } }

    /// The three newest runs. The current run comes from the store, so it is live.
    private var recent: [RunState] {
        var runs = history.runs
        if let live = snap.run {
            if let i = runs.firstIndex(where: { $0.id == live.id }) { runs[i] = live } else { runs.insert(live, at: 0) }
        }
        return Array(runs.prefix(3))
    }

    var body: some View {
        WinScroll {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 30)
                if needsCount > 0 {
                    needs
                } else if !running {
                    allClear
                }
                if !recent.isEmpty {
                    recentSection
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, WinMetrics.titlebarZone)
            .padding(.bottom, 26)
            .sheet(item: $history.opened) { row in
                ReviewSheet(row: row, text: store.reviewText(runId: row.runId, slug: row.repo, n: row.number), store: store) {
                    history.opened = nil
                }
            }
        }
        .sheet(isPresented: $reviewModel.open) {
            ReviewNowSheet(store: store, model: reviewModel)
        }
        .onAppear { history.load(store) }
        .onChange(of: RunsKey(snap)) { _, _ in history.load(store) }
        // The review sheet opened here takes the same shortcuts as one opened from History.
        .onChange(of: history.opened?.id) { _, _ in ShortcutContext.shared.setReview(history.opened) }
        .onDisappear { ShortcutContext.shared.setReview(nil) }
    }

    // MARK: Header

    /// The title on the left; the status line and the Review menu on the right, on one row.
    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Now")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Gotham.fg)
            Spacer(minLength: 8)
            statusLine
            reviewMenu
        }
    }

    private var statusLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(statusText(at: snap.now ?? context.date))
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .monospacedDigit()
        }
    }

    /// "Next sweep 8:00 PM · in 3 h 41 min", "Paused", "Sweeping · m:ss", or "Reviewing <run> · m:ss" for a by-hand run.
    private func statusText(at date: Date) -> String {
        if running, let run = snap.run {
            let elapsed = Self.elapsed(date.timeIntervalSince(run.started))
            if run.kind == nil { return "Sweeping · \(elapsed)" }
            return "Reviewing \(RunDigest.title(for: run)) · \(elapsed)"
        }
        if snap.paused { return "Paused" }
        guard let next = snap.nextRun else { return "No sweep scheduled" }
        return "Next sweep \(HeaderCopy.clock(next)) · in \(HeaderCopy.untilText(next, date))"
    }

    /// "m:ss", or "h:mm:ss" from an hour on.
    static func elapsed(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = s / 60 % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    /// The primary Review menu: a sweep, one PR or several by URL or number, or one author's PRs.
    @ViewBuilder
    private var reviewMenu: some View {
        if offscreen {
            // ImageRenderer draws AppKit menus as a prohibition sign; the pill stands in for the menu.
            reviewLabel
        } else {
            Menu {
                Button("Sweep all repos now") { Confirm.run(store) }
                    .disabled(running || snap.dryRunning || !snap.jobInstalled)
                Button("Review PRs…") { openReviewSheet(.pr) }
                Button("Review someone's PRs…") { openReviewSheet(.author) }
            } label: {
                reviewLabel
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var reviewLabel: some View {
        Text("Review…")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(hex: "08080A"))
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Capsule().fill(Gotham.fg))
    }

    private func openReviewSheet(_ mode: ReviewSheetModel.Mode) {
        reviewModel.show(repos: snap.config?.repos.map(\.slug) ?? [])
        reviewModel.mode = mode
        if mode == .author { reviewModel.load(store: store) }
    }

    // MARK: Needs you

    private var needs: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                capLabel("Needs you")
                capLabel("\(needsCount)", signal)
            }
            .padding(.bottom, 10)
            VStack(spacing: 6) {
                ForEach(held) { strip in heldRow(strip) }
                ForEach(tooLarge) { strip in tooLargeRow(strip) }
                ForEach(tendNeeds, id: \.id) { item in
                    TendNeedRow(item: item, url: store.approachPlane(item.slug, item.n)?.url ?? "", store: store)
                }
            }
        }
    }

    private func heldRow(_ strip: Strip) -> some View {
        let changes = strip.verdict == .changes
        let verdictColour = changes ? signal : Gotham.fg
        let detail = [strip.reason, "\(strip.repo) #\(strip.number)"].compactMap { $0 }.joined(separator: " · ")
        return HStack(spacing: 12) {
            AvatarView(login: strip.author ?? "pr", size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(strip.title ?? "#\(strip.number)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                (Text(changes ? "Changes" : "Approved")
                    .foregroundStyle(verdictColour)
                    .fontWeight(.semibold)
                 + Text(verbatim: " · \(detail)")
                    .foregroundStyle(Gotham.mute))
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
            .onTapGesture { history.focus(strip.id, store: store) }
            Spacer(minLength: 8)
            heldActions(strip, tint: verdictColour)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(signal.opacity(0.07)))
    }

    /// A PR the newest run skipped for size. Review anyway goes through the Review confirm; the warning is its tooltip.
    private func tooLargeRow(_ strip: Strip) -> some View {
        let lines = (strip.changedLines ?? 0).formatted()
        let detail = "Too large · \(lines) lines · \(strip.repo) #\(strip.number)"
        return HStack(spacing: 12) {
            AvatarView(login: strip.author ?? "pr", size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(strip.title ?? "#\(strip.number)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                Text(verbatim: detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            WinButton(title: "Review anyway", style: .outline, small: true) {
                Confirm.review(store, .prs([PRRef(slug: strip.repo, n: strip.number)]))
            }
            .disabled(running)
            .help(store.reviewWarning(strip))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Gotham.row))
    }

    /// Discard, and Hold to post: posting publishes, so it stays a hold. Shows the work in progress once one starts.
    @ViewBuilder
    private func heldActions(_ strip: Strip, tint: Color) -> some View {
        if let busy = store.draftBusy[strip.id] {
            Text(busy == .posting ? "Posting…" : "Discarding…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Gotham.mute)
        } else {
            HStack(spacing: 8) {
                Button("Discard") { Confirm.discard(strip, store: store) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Gotham.mute)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                    .disabled(store.snap.running)
                HoldButton(title: "Hold to post", doneTitle: "Posting…", tint: tint) {
                    store.postDraft(strip)
                }
                .id(strip.id)
                .frame(width: 150)
                .disabled(store.snap.running)
            }
        }
    }

    // MARK: All clear

    private var allClear: some View {
        VStack(spacing: 6) {
            Text("Nothing needs you")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Gotham.fg)
            Text(cleanFinish ? "Every open PR is reviewed at its latest commit." : "No reviews are waiting to be posted.")
                .font(.system(size: 13))
                .foregroundStyle(Gotham.mute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Recent

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            capLabel("Recent")
                .padding(.top, 10)
                .padding(.bottom, 10)
            ForEach(recent, id: \.id) { run in
                RunCard(run: run, running: running && run.id == snap.run?.id, store: store) { stripID in
                    history.open(runID: run.id, stripID: stripID, store: store)
                }
            }
        }
    }
}

// MARK: Shared parts

/// A ring that breathes: a halo grows and fades on `period`. Still under reduced motion.
struct Pulse: View {
    let colour: Color
    let period: Double

    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = Motion.reduced(reduceMotion)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
            let k = still ? 0 : (1 - cos(2 * Double.pi * context.date.timeIntervalSinceReferenceDate / period)) / 2
            ZStack {
                Circle()
                    .fill(colour.opacity(0.06 + 0.24 * k))
                    .frame(width: 10 + 12 * k, height: 10 + 12 * k)
                Circle().strokeBorder(colour, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            }
            .frame(width: 10, height: 10)
        }
    }
}

/// Small caps: the cap style from `Gotham`, with a colour for the words that carry one.
func capLabel(_ text: String, _ colour: Color = Gotham.mute) -> some View {
    Text(text)
        .font(.system(size: 9.5, weight: .semibold))
        .tracking(1.9)
        .textCase(.uppercase)
        .foregroundStyle(colour)
}

/// The row parts the onboarding first sweep shares with the Now rows (kept here from the old Overview): the stage meter, the stage word, and the verdict
/// mark with its word in the fixed 88 pt column.
enum RunRowViews {
    /// Four 12x4 dashes: done faint, the current stage blue, the rest dim.
    static func meter(_ segments: [MeterSegment]) -> some View {
        HStack(spacing: WinMetrics.s4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(meterColour(segment))
                    .frame(width: 12, height: 4)
            }
        }
    }

    static func meterColour(_ segment: MeterSegment) -> Color {
        switch segment {
        case .done: return Color.primary.opacity(0.35)
        case .current: return WinTheme.blue
        case .future: return Color.primary.opacity(0.12)
        }
    }

    static func phaseWord(_ row: RowModel) -> String {
        if case .active(let phase) = row.status { return phase }
        return ""
    }

    /// Mark and word in the fixed 88 pt status column.
    @ViewBuilder
    static func verdict(_ row: RowModel) -> some View {
        HStack(spacing: WinMetrics.s8) {
            switch row.status {
            case .changes:
                Text("Changes").foregroundStyle(WinTheme.amberInk)
                StatusTriangle().fill(WinTheme.amber).frame(width: 8, height: 7)
            case .approved:
                Text("Approved").foregroundStyle(WinTheme.green)
                Circle().fill(WinTheme.green).frame(width: 7, height: 7)
            case .skipped:
                Text("Skipped").foregroundStyle(WinTheme.faint)
                Rectangle().fill(WinTheme.faint).frame(width: 8, height: 2)
            default:
                EmptyView()
            }
        }
        .font(.system(size: 12, weight: .medium))
        .frame(width: 88, alignment: .trailing)
    }
}
