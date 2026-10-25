import SwiftUI

/// The Now section (prototype `#now`): the clock, the sweep's stats and control, the repo rail, and one pipeline row per
/// PR in the run. Rows come from `Presentation.rows`, so they sort as the popover sorts them. A finished row opens its
/// review in Reviews.
struct NowView: View {
    @ObservedObject var store: Store
    @ObservedObject var router: WindowRouter
    @AppStorage("signalColour") private var signalKey = "amber"
    /// The "Review a PR or author…" sheet's state. Owned here, as `ReposView` owns its `ReposModel`.
    @StateObject private var reviewModel = ReviewSheetModel()

    private var snap: Snapshot { store.snap }
    private var run: RunState? { snap.run }
    private var running: Bool { snap.running }
    private var signal: Color { Gotham.signal(signalKey) }

    /// Every PR of the run, in the popover's order.
    private var rows: [RowModel] {
        Presentation.rows(from: store.strips, running: running, repos: run?.repos ?? []).flatMap(\.rows)
    }

    /// The repos in config order, or in the run's order when there is no config.
    private var repoOrder: [String] {
        snap.config?.repos.map(\.slug) ?? run?.repos.map(\.slug) ?? []
    }

    /// The repo the runner is on. Its phase names the repo ("listing PRs in owner/name"); otherwise the repo of an
    /// in-flight PR. Nil when nothing runs.
    private var currentRepo: String? {
        guard running else { return nil }
        if let phase = run?.phase, let slug = repoOrder.first(where: { phase.hasSuffix($0) }) { return slug }
        return rows.first { $0.strip.active && $0.strip.verdict == nil }?.strip.repo
    }

    /// "Listing PRs", "Indexing" or "Reviewing", from the runner's phase.
    private var phaseLabel: String? {
        guard running else { return nil }
        guard let phase = run?.phase else { return "Reviewing" }
        if phase.hasPrefix("listing") { return "Listing PRs" }
        if phase.hasPrefix("indexing") { return "Indexing" }
        return "Reviewing"
    }

    private var caption: String {
        if running {
            return ["Sweeping", currentRepo, phaseLabel].compactMap { $0 }.joined(separator: " · ")
        }
        return snap.paused ? "Paused" : "Next sweep"
    }

    var body: some View {
        WinScroll {
            VStack(alignment: .leading, spacing: 0) {
                Text("Now")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.8)
                    .foregroundStyle(Gotham.fg)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, WinMetrics.s16)
                nowTop
                rail
                    .padding(.bottom, 28)
                header
                LazyVStack(spacing: 8) {
                    if rows.isEmpty {
                        capLabel("Nothing in flight")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                    ForEach(rows) { row in
                        pipeRow(row)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, WinMetrics.titlebarZone)
            .padding(.bottom, 26)
        }
        .sheet(isPresented: $reviewModel.open) {
            ReviewNowSheet(store: store, model: reviewModel)
        }
    }

    // MARK: Top

    private var nowTop: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .bottom, spacing: 26) {
                VStack(alignment: .leading, spacing: 12) {
                    ClockFace(snap: snap)
                    capLabel(caption)
                }
                Spacer(minLength: 0)
                control
                    .frame(width: 170)
                    .padding(.bottom, 14)
            }
            HStack(alignment: .top, spacing: 26) {
                stat(compactTokens(runTokens), running ? "Tokens" : "Last tokens")
                stat("\(rows.filter { $0.status == .queued }.count)", "Queued")
                stat("\(rows.filter { $0.strip.awaitsHold }.count)", "Waiting")
                stat(lastDuration, "Last sweep")
            }
        }
        .padding(.bottom, 30)
    }

    /// The run's tokens. `run.tokens` is written only when the sweep finishes, so the in-flight session is added on top.
    private var runTokens: Int {
        (run?.tokens ?? 0) + (running ? store.liveTokens.total : 0)
    }

    @ViewBuilder
    private var control: some View {
        if running {
            HoldButton(title: "Hold to stop", doneTitle: "Stopping…", tint: Gotham.fg) { store.stopRun() }
                .id(run?.id ?? "")
                .overlay {
                    Tracer(shape: Capsule(), lineWidth: 1)
                        .allowsHitTesting(false)
                }
        } else {
            VStack(spacing: 8) {
                Button {
                    Confirm.run(store)
                } label: {
                    Text("Run now")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Gotham.fg)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(Gotham.row))
                        .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!snap.jobInstalled || snap.dryRunning)
                WinButton(title: "Review a PR or author…", style: .link, small: true) {
                    reviewModel.show(repos: snap.config?.repos.map(\.slug) ?? [])
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value)
                .font(.system(size: 24, weight: .light))
                .tracking(-0.5)
                .monospacedDigit()
                .foregroundStyle(Gotham.fg)
            capLabel(label)
        }
    }

    /// The last finished sweep's length. A sweep in flight has none yet.
    private var lastDuration: String {
        guard !running, let run, let finished = run.finished else { return "—" }
        let s = Int(finished.timeIntervalSince(run.started))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(String(format: "%02d", s % 60))s"
    }

    // MARK: Rail

    private enum RailState { case done, act, pending }

    private func railState(_ slug: String) -> RailState {
        guard run != nil else { return .pending }
        guard running else { return .done }
        guard let current = currentRepo, let ci = repoOrder.firstIndex(of: current),
              let i = repoOrder.firstIndex(of: slug) else { return .pending }
        if i == ci { return .act }
        return i < ci ? .done : .pending
    }

    /// One column per repo, in config order: its name over a 2 pt line. The repo being swept traces its line.
    private var rail: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(repoOrder, id: \.self) { slug in
                let state = railState(slug)
                VStack(alignment: .leading, spacing: 0) {
                    capLabel(state == .act ? "\(slug) · \(phaseLabel ?? "")" : slug,
                             state == .act ? Gotham.fg : Gotham.mute)
                        .lineLimit(1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(state == .done ? Gotham.fg : Gotham.edge)
                        if state == .act { LineSweep() }
                    }
                    .frame(height: 2)
                    .clipShape(Capsule())
                    .padding(.top, 9)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Pipeline

    private var header: some View {
        HStack(spacing: 22) {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
            HStack(spacing: 0) {
                capLabel("Gather").frame(maxWidth: .infinity, alignment: .leading)
                capLabel("Review").frame(maxWidth: .infinity)
                capLabel("Check").frame(maxWidth: .infinity)
                capLabel("Land").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .frame(minWidth: 170, maxWidth: 280)
            capLabel("Tokens")
                .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func pipeRow(_ row: RowModel) -> some View {
        let s = row.strip
        let queued = row.status == .queued
        let inFlight = running && s.active && s.verdict == nil
        let pipe = StageTrack(strip: s)
        return HStack(spacing: 22) {
            HStack(spacing: 12) {
                AvatarView(login: s.author ?? "pr", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(s.author ?? "#\(s.number)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Gotham.fg)
                            .lineLimit(1)
                        if s.isDraftPR {
                            Text("Draft PR")
                                .font(.system(size: 9, weight: .semibold))
                                .tracking(1.6)
                                .textCase(.uppercase)
                                .foregroundStyle(Gotham.mute)
                        }
                    }
                    Text(s.title ?? "#\(s.number)")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Gotham.mute)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { i in
                    NodeDot(node: pipe.nodes[i], signal: signal)
                    if i < 3 {
                        LinkLine(state: pipe.links[i])
                    }
                }
            }
            .frame(minWidth: 170, maxWidth: 280)

            VStack(alignment: .trailing, spacing: 5) {
                Text(tokenText(row))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Gotham.fg)
                capLabel(endWord(row), endColour(row))
            }
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Gotham.row))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
        .overlay {
            if inFlight {
                Tracer(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .opacity(queued ? 0.4 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            if s.verdict != nil { router.openReview(s.id) }
        }
    }

    /// The token count: the PR's own once recorded, else the live count for its number while it runs.
    private func tokenText(_ row: RowModel) -> String {
        let live = row.strip.active ? store.liveTokens.byPR[row.strip.number] ?? 0 : 0
        let n = row.strip.tokens > 0 ? row.strip.tokens : live
        return n > 0 ? compactTokens(n) : "—"
    }

    /// The word under the tokens: the stage while in flight, Waiting for a held draft, else the verdict.
    private func endWord(_ row: RowModel) -> String {
        let s = row.strip
        if case .active(let phase) = row.status { return phase }
        if row.status == .queued { return "Queued" }
        if s.draft { return "Waiting" }
        switch s.verdict {
        case .changes?: return "Changes"
        case .approve?: return "Approved"
        case .skipped?: return "Skipped"
        case nil: return "No result"
        }
    }

    private func endColour(_ row: RowModel) -> Color {
        switch row.strip.verdict {
        case .changes?: return signal
        case .approve?: return Gotham.fg
        default: return Gotham.mute
        }
    }
}

// MARK: Pipeline parts

/// Gather, Review, Check, Land: the four nodes and their links for one PR.
struct StageTrack {
    enum Node: Equatable {
        case off, on, current, land(Colour), wait
    }
    enum Link: Equatable {
        case off, on, run
    }
    /// Colour as a value, so the struct stays Equatable.
    enum Colour: Equatable { case approve, signal }

    let nodes: [Node]
    let links: [Link]

    init(strip s: Strip) {
        // The stage a running PR is in (1...4). Other PRs have no current stage.
        let current: Int? = s.active && s.verdict == nil ? min(max(s.stage, 1), 4) : nil
        // How far a finished PR got: a skip stops at Gather, a held draft at Check, a landed review at Land.
        let reached: Int
        if s.verdict == .skipped { reached = 1 } else if s.draft { reached = 3 } else if s.verdict != nil { reached = 4 } else { reached = 0 }
        let held = s.draft && s.verdict != nil
        let landed: Colour? = s.verdict == nil || s.verdict == .skipped ? nil : (s.verdict == .changes ? .signal : .approve)

        nodes = (1...4).map { i in
            if let current { return i < current ? .on : i == current ? .current : .off }
            if i == 4, held { return .wait }
            if i == 4, reached == 4, let landed { return .land(landed) }
            return i <= reached ? .on : .off
        }
        links = (1...3).map { i in
            if let current { return i + 1 == current ? .run : i + 1 < current ? .on : .off }
            return i + 1 <= reached ? .on : .off
        }
    }
}

/// One node of the pipeline. The current one and a held review pulse.
struct NodeDot: View {
    let node: StageTrack.Node
    let signal: Color

    var body: some View {
        switch node {
        case .off:
            Circle().strokeBorder(Gotham.edge, lineWidth: 1.5)
                .frame(width: 10, height: 10)
        case .on:
            Circle().fill(Gotham.fg)
                .shadow(color: .white.opacity(0.35), radius: 4)
                .frame(width: 10, height: 10)
        case .land(let colour):
            Circle().fill(colour == .approve ? Gotham.approve : signal)
                .shadow(color: colour == .approve ? Gotham.approve : signal, radius: 6)
                .frame(width: 10, height: 10)
        case .current:
            Pulse(colour: Gotham.fg, period: 1.4)
        case .wait:
            Pulse(colour: signal, period: 2.4)
        }
    }
}

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

/// A link between two nodes: grey, silver when reached, with the highlight running along it while its stage is live.
struct LinkLine: View {
    let state: StageTrack.Link

    var body: some View {
        Capsule()
            .fill(state == .on ? Gotham.fg : Gotham.edge)
            .frame(height: 1.5)
            .overlay {
                if state == .run { LineSweep() }
            }
            .clipShape(Capsule())
            .padding(.horizontal, 5)
            .frame(maxWidth: .infinity)
    }
}

/// The highlight that runs along a line (prototype `trace`, 1.1 s). Still under reduced motion.
struct LineSweep: View {
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let still = Motion.reduced(reduceMotion)
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: still)) { context in
                let w = geo.size.width
                let t = still ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.1) / 1.1
                LinearGradient(colors: [.clear, .white, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w * 0.45, height: geo.size.height)
                    .offset(x: -w * 0.45 + t * w * 1.485)
                    .opacity(still ? 0 : 1)
                    .frame(width: w, height: geo.size.height, alignment: .leading)
            }
        }
        .clipped()
    }
}

/// The clock: elapsed time while a sweep runs, the countdown to the next sweep otherwise. Ticks once a second.
struct ClockFace: View {
    let snap: Snapshot

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(text(at: snap.now ?? context.date))
                .font(Gotham.numeral(92))
                .tracking(-4.5)
                .monospacedDigit()
                .foregroundStyle(Gotham.fg)
        }
    }

    private func text(at date: Date) -> String {
        if snap.running, let run = snap.run {
            return Self.format(date.timeIntervalSince(run.started))
        }
        guard let next = snap.nextRun else { return "--:--" }
        return Self.format(next.timeIntervalSince(date))
    }

    /// "mm:ss", or "h:mm:ss" from an hour on.
    static func format(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = s / 60 % 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
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
