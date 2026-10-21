import SwiftUI
import AppKit

/// The Overview section (v1.2 mockups 4-overview and 5-running). The hero is the stripe field with the glide dot,
/// the headline from `HeaderCopy`, one line, and one action. Below it: two panels when idle, or one panel while a
/// sweep runs.
struct OverviewView: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var p: Palette { Palette(scheme) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let kind = Presentation.headerKind(store.snap, now: context.date)
            let copy = HeaderCopy.make(kind, now: context.date, drafts: store.draftCount)
            VStack(spacing: 0) {
                field
                VStack(spacing: 0) {
                    Text(copy.headline)
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(tone(copy.headlineTone))
                        .lineLimit(1)
                        .padding(.top, WinMetrics.s24)
                    if let line = subline(kind, copy) {
                        Text(line)
                            .font(.system(size: 13))
                            .foregroundStyle(WinTheme.muted)
                            .lineLimit(1)
                            .padding(.top, WinMetrics.s4)
                    }
                    heroActions(kind)
                        .padding(.top, WinMetrics.s20)
                }
                .frame(maxWidth: .infinity)

                Group {
                    if store.snap.running {
                        onApproach
                    } else {
                        idleColumns
                    }
                }
                .padding(.top, WinMetrics.s32)
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: Hero

    /// The field runs the canvas width, bleeding past the 32 pt inset as the mockup does. The dot glides from the
    /// disc edge to touchdown and back on a 4 s ease-in-out loop, and rests at touchdown when idle or when
    /// Reduce Motion is on.
    private var field: some View {
        TimelineView(.animation(paused: !store.snap.running || reduceMotion)) { context in
            HeroField(t: store.snap.running && !reduceMotion ? HeroField.glide(context.date) : 1)
        }
        .frame(height: 176)
        .padding(.horizontal, -WinMetrics.canvasLeft)
    }

    @ViewBuilder
    private func heroActions(_ kind: HeaderKind) -> some View {
        HStack(spacing: WinMetrics.s16) {
            if store.snap.running {
                WinButton(title: "Stop sweep", style: .outline, large: true) { confirmAndStop() }
            } else if store.snap.paused {
                WinButton(title: "Resume", style: .primary) { store.togglePause() }
            } else {
                WinButton(title: "Run sweep now", style: .primary) { confirmAndRun() }
                    .disabled(!store.snap.jobInstalled)
            }
            if case .failed = kind {
                WinButton(title: "Open log", style: .outline) { store.openLog() }
            }
        }
    }

    /// The line under the headline: the run's own numbers, or the header copy's line 2 for the other states.
    private func subline(_ kind: HeaderKind, _ copy: HeaderCopy) -> String? {
        let run = store.snap.run
        var parts: [String] = []
        switch kind {
        case .running(let changes, _, _, let done, let started):
            if let started { parts.append("Started \(HeaderCopy.clock(started))") }
            parts.append("\(done) landed")
            if changes > 0 { parts.append("\(changes) need changes") }
            if let run, run.tokens > 0 { parts.append("\(compactTokens(run.tokens)) tokens so far") }
        case .idle(_, _, let started, let total):
            if let started { parts.append("Last sweep \(when(started))") }
            var prs = "\(total) PR\(total == 1 ? "" : "s")"
            if let run, let finished = run.finished {
                prs += " in \(max(1, Int(finished.timeIntervalSince(run.started) / 60))) min"
            }
            parts.append(prs)
            if let run, run.tokens > 0 { parts.append("\(compactTokens(run.tokens)) tokens") }
        default:
            return copy.line2
        }
        return parts.joined(separator: " · ")
    }

    /// "today at 1:00 PM", or the date and time for an earlier sweep.
    private func when(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "today at \(HeaderCopy.clock(date))"
            : date.formatted(.dateTime.month().day().hour().minute())
    }

    private func tone(_ t: HeaderCopy.Tone) -> Color {
        switch t {
        case .ink: return WinTheme.text
        case .secondary: return WinTheme.muted
        case .tertiary: return WinTheme.faint
        case .changes: return WinTheme.amberInk
        case .error: return p.error
        }
    }

    // MARK: Idle

    private var idleColumns: some View {
        HStack(alignment: .top, spacing: WinMetrics.s16) {
            waitingPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            lastSweepPanel.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Drafts to post, then PRs too large to review on their own. Each row offers its one action.
    private var waiting: [Strip] {
        store.strips.filter { $0.draft || ($0.skipReason == "size" && $0.verdict == .skipped) }
    }

    private var waitingPanel: some View {
        let items = waiting
        return panel("Waiting on you", meta: "\(items.count)", rows: {
            if items.isEmpty {
                Text("Nothing waiting on you.")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                    .frame(height: 56, alignment: .leading)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { index, strip in
                    waitingRow(strip, first: index == 0)
                }
            }
        }, footer: {
            WinButton(title: "Open all in Reviews", style: .link) { WindowRouter.shared.open(.reviews) }
        })
    }

    private func waitingRow(_ strip: Strip, first: Bool) -> some View {
        rowView(first: first, title: strip.title ?? "#\(strip.number)", meta: {
            Text(waitingMeta(strip))
                .foregroundStyle(strip.draftError == nil ? WinTheme.faint : p.error)
        }, trailing: {
            HStack(spacing: WinMetrics.s16) {
                waitingActions(strip)
            }
            .disabled(store.snap.running)
        })
    }

    private func waitingMeta(_ strip: Strip) -> String {
        if let error = strip.draftError { return error }
        let place = "\(strip.repo) #\(strip.number)"
        if strip.draft {
            let verdict: String? = strip.verdict == .changes ? "changes requested"
                : (strip.verdict == .approve ? "approve" : nil)
            return verdict.map { "\(place) · draft, \($0)" } ?? "\(place) · draft"
        }
        return "\(place) · too large, \((strip.changedLines ?? 0).formatted()) lines"
    }

    @ViewBuilder
    private func waitingActions(_ strip: Strip) -> some View {
        if let action = strip.draftAction {
            Text(action == .posting ? "Posting…" : "Discarding…")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WinTheme.blue)
        } else if strip.draft {
            WinButton(title: "Post", style: .link) { confirmAndPost(strip) }
            WinButton(title: "Discard", style: .quiet) { store.discardDraft(strip) }
        } else {
            WinButton(title: "Review", style: .link) { confirmAndReview(strip) }
        }
    }

    /// The last finished sweep's landed PRs, changes first, three of them.
    private var landed: [RowModel] {
        rows.filter { $0.strip.verdict != nil }
    }

    private var lastSweepPanel: some View {
        return panel("Last sweep", meta: store.snap.run.map { HeaderCopy.clock($0.started) }, rows: {
            if landed.isEmpty {
                Text("No sweep yet.")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                    .frame(height: 56, alignment: .leading)
            } else {
                ForEach(Array(landed.prefix(3).enumerated()), id: \.offset) { index, row in
                    landedRow(row, first: index == 0)
                }
            }
        }, footer: {
            WinButton(title: "See all \(rows.count)", style: .link) { WindowRouter.shared.open(.reviews) }
        })
    }

    private func landedRow(_ row: RowModel, first: Bool) -> some View {
        let strip = row.strip
        let place = "\(strip.repo) #\(strip.number)"
        return rowView(first: first, title: strip.title ?? "#\(strip.number)", meta: {
            HStack(spacing: 0) {
                if let reason = strip.reason {
                    Text(reason).foregroundStyle(WinTheme.amberInk)
                    Text(" · \(place)").foregroundStyle(WinTheme.faint)
                } else {
                    Text(place + (strip.author.map { " · \($0)" } ?? "")).foregroundStyle(WinTheme.faint)
                }
            }
        }, trailing: {
            verdictStatus(row)
        })
    }

    /// Mark and word in the fixed 88 pt status column.
    @ViewBuilder
    private func verdictStatus(_ row: RowModel) -> some View {
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

    // MARK: Running

    private var inFlight: [RowModel] {
        rows.filter { $0.meter != nil }
    }

    private var onApproach: some View {
        let items = inFlight
        return panel("On approach", meta: "\(items.count) in flight · \(landed.count) landed", rows: {
            ForEach(Array(items.enumerated()), id: \.offset) { index, row in
                approachRow(row, first: index == 0)
            }
        }, footer: {
            WinButton(title: "Open the log", style: .link) { store.openLog() }
        })
    }

    private func approachRow(_ row: RowModel, first: Bool) -> some View {
        let strip = row.strip
        let place = "\(strip.repo) #\(strip.number)" + (strip.author.map { " · \($0)" } ?? "")
        return rowView(first: first, title: strip.title ?? "#\(strip.number)", meta: {
            Text(place).foregroundStyle(WinTheme.faint)
        }, trailing: {
            HStack(spacing: WinMetrics.s16) {
                meter(row.meter ?? [])
                Text(phaseWord(row))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WinTheme.blue)
                    .frame(width: 88, alignment: .trailing)
            }
        })
    }

    /// Four 12x4 dashes: done faint, the current stage blue, the rest dim.
    private func meter(_ segments: [MeterSegment]) -> some View {
        HStack(spacing: WinMetrics.s4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(meterColour(segment))
                    .frame(width: 12, height: 4)
            }
        }
    }

    private func meterColour(_ segment: MeterSegment) -> Color {
        switch segment {
        case .done: return Color.primary.opacity(0.35)
        case .current: return WinTheme.blue
        case .future: return Color.primary.opacity(0.12)
        }
    }

    private func phaseWord(_ row: RowModel) -> String {
        if case .active(let phase) = row.status { return phase }
        return ""
    }

    // MARK: Shared

    /// Every PR of the current run, grouped and ranked as the popover ranks them.
    private var rows: [RowModel] {
        Presentation.rows(from: store.strips, running: store.snap.running, repos: store.snap.run?.repos ?? [])
            .flatMap(\.rows)
    }

    /// A panel (surface, radius 14, padding 16/20): a 28 pt header, the rows, and a 44 pt footer pinned to the
    /// bottom, so two panels side by side end level.
    private func panel<Body: View, Foot: View>(_ title: String, meta: String?,
                                               @ViewBuilder rows: () -> Body,
                                               @ViewBuilder footer: () -> Foot) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: WinMetrics.s8) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WinTheme.text)
                Spacer(minLength: 0)
                if let meta {
                    Text(meta)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .monospacedDigit()
                }
            }
            .frame(height: 28)
            rows()
            Spacer(minLength: 0)
            footer()
                .frame(height: 44)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) {
                    Rectangle().fill(WinTheme.line).frame(height: 1)
                }
        }
        .padding(.horizontal, WinMetrics.s20)
        .padding(.top, WinMetrics.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(WinTheme.surface))
    }

    /// A 56 pt row: title (13 medium) over meta (12), the trailing content in its own column. The rule is drawn
    /// inside the row's top edge, so it adds no height.
    private func rowView<Meta: View, Trailing: View>(first: Bool, title: String,
                                                     @ViewBuilder meta: () -> Meta,
                                                     @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: WinMetrics.s16) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WinTheme.text)
                    .lineLimit(1)
                    .frame(height: 20, alignment: .leading)
                meta()
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .frame(height: 16, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(height: 56)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(WinTheme.line).frame(height: 1)
            }
        }
    }

    // MARK: Confirmations (the same alerts as the popover)

    private func confirmAndRun() {
        if store.snap.postsReviews {
            let alert = NSAlert()
            alert.messageText = "Run the review pipeline now?"
            alert.informativeText = "Some repos post reviews with posting = \"review\", which show as real reviews on GitHub."
            alert.addButton(withTitle: "Run now")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        store.runNow()
    }

    private func confirmAndStop() {
        let alert = NSAlert()
        alert.messageText = "Stop the current sweep?"
        alert.informativeText = "Reviews already posted stay posted."
        alert.addButton(withTitle: "Stop")
        alert.addButton(withTitle: "Keep running")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.stopRun()
    }

    private func confirmAndPost(_ strip: Strip) {
        let preview = store.draftPreview(strip)
        let alert = NSAlert()
        alert.messageText = "Post the review on \(strip.repo) #\(strip.number)?"
        alert.informativeText = preview.verdict + "\n\n" + preview.body
        alert.addButton(withTitle: "Post")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.postDraft(strip)
    }

    private func confirmAndReview(_ strip: Strip) {
        let alert = NSAlert()
        alert.messageText = "Review #\(strip.number) anyway?"
        alert.informativeText = store.reviewWarning(strip)
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.reviewPR(strip)
    }
}
