import SwiftUI
import AppKit

/// The review sheet as a flight recorder: the approach a PR made through its run (gather, review, check, land), the
/// verdict, and the readouts behind each stage. Drawn from prototype docs/design/run-detail/prototype.html.

/// The artifacts a review sheet shows. Starts empty and fills off the main thread; a fixture starts loaded.
@MainActor
final class RunArtifactsModel: ObservableObject {
    @Published private(set) var artifacts: RunArtifacts?
    @Published private(set) var loaded: Bool
    private var requested = false

    init(fixture: RunArtifacts? = nil) {
        artifacts = fixture
        loaded = fixture != nil
    }

    /// Reads the PR folder once, off the main actor.
    func load(folder: String) {
        guard !loaded, !requested else { return }
        requested = true
        Task {
            let found = await Task.detached(priority: .userInitiated) { RunArtifacts.load(folder: folder) }.value
            artifacts = found
            loaded = true
        }
    }
}

/// The motion and pointer state of the sheet: the approach's draw-in, the touchdown halo, the hovered waypoint and the
/// readout a click highlights. `play` runs the draw-in once when the sheet opens.
@MainActor
final class FlightModel: ObservableObject {
    /// How much of the slope is drawn, 0 to 1.
    @Published var draw: CGFloat = 0
    @Published var waypoints = false
    @Published var figures = false
    @Published var goAround = false
    /// The halo shows at rest once `fired`, then grows and fades as `halo` runs from 0 to 1.
    @Published var fired = false
    @Published var halo: CGFloat = 0
    @Published var hot: Int?
    @Published var flashed: FlightReadout?

    func play(duration: Double) {
        draw = 1
        waypoints = true
        figures = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard let self else { return }
            self.goAround = true
            self.fired = true
            // One frame at rest, so the halo starts from its own state rather than the last one.
            try? await Task.sleep(nanoseconds: 20_000_000)
            withAnimation(.timingCurve(0.2, 0.7, 0.1, 1, duration: 0.9)) { self.halo = 1 }
        }
    }

    func flash(_ readout: FlightReadout) {
        flashed = readout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 900_000_000)
            if self?.flashed == readout { self?.flashed = nil }
        }
    }
}

/// The readouts under the verdict bar, for a waypoint or a scroll target.
enum FlightReadout: Hashable {
    case review, checker, blast, notes, gathered
}

/// One stage's figure under the approach: a bold line and an optional muted line.
struct FigureText: Equatable {
    let title: String
    let sub: String?
}

/// Colours and text helpers the flight recorder shares.
enum FlightText {
    static let loc = Color(hex: "8FB0FF")
    static let faint = Color(hex: "ECECF2").opacity(0.22)

    /// Markdown with inline code only. Code spans draw in 12 pt monospaced fg.
    static func styled(_ text: String) -> AttributedString {
        var out = (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        let code = out.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map(\.range)
        for range in code {
            out[range].font = .system(size: 12, design: .monospaced)
            out[range].foregroundColor = Gotham.fg
        }
        return out
    }

    /// The text up to the first full stop that ends a sentence, or the first line.
    static func firstSentence(_ text: String) -> String {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? ""
        guard let stop = line.range(of: ". ") else { return line }
        return String(line[..<stop.lowerBound]) + "."
    }
}

/// The approach's drawing space: the prototype's 800 x 206 grid, scaled to the width.
enum ApproachSpace {
    static let width: CGFloat = 800
    static let height: CGFloat = 206
    static let xs: [CGFloat] = [56, 262, 468, 674]
    static let ys: [CGFloat] = [44, 72, 100, 128]
    static let touchdown = CGPoint(x: 734, y: 150)

    static func transform(_ rect: CGRect) -> CGAffineTransform {
        CGAffineTransform(scaleX: rect.width / width, y: rect.height / height)
    }

    /// Stage i's waypoint in the drawing space. A landed review's Land sits on the runway.
    static func point(_ i: Int, landed: Bool) -> CGPoint {
        i == 3 && landed ? touchdown : CGPoint(x: xs[i], y: ys[i])
    }
}

/// The glide slope through every reached waypoint. A landed review flares onto the runway.
struct SlopeShape: Shape {
    let reached: Int
    let landed: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: ApproachSpace.xs[0], y: ApproachSpace.ys[0]))
        if reached <= 1 {
            p.addLine(to: CGPoint(x: ApproachSpace.xs[0] + 0.1, y: ApproachSpace.ys[0]))
        }
        if reached > 1 {
            for i in 1..<reached {
                if i == 3 && landed {
                    p.addLine(to: CGPoint(x: 644, y: 132))
                    p.addQuadCurve(to: ApproachSpace.touchdown, control: CGPoint(x: 674, y: 148))
                    p.addLine(to: CGPoint(x: 792, y: 150))
                } else {
                    p.addLine(to: CGPoint(x: ApproachSpace.xs[i], y: ApproachSpace.ys[i]))
                }
            }
        }
        return p.applying(ApproachSpace.transform(rect))
    }
}

/// The dashed go-around: a pull-up from the gather waypoint when the review stopped.
struct GoAroundShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 56, y: 44))
        p.addLine(to: CGPoint(x: 126, y: 53))
        p.addCurve(to: CGPoint(x: 246, y: 14), control1: CGPoint(x: 176, y: 59), control2: CGPoint(x: 206, y: 46))
        return p.applying(ApproachSpace.transform(rect))
    }
}

/// The dotted guide from the top of the approach down to the runway.
struct ApproachGuide: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 8, y: 40))
        p.addLine(to: CGPoint(x: 792, y: 136))
        return p.applying(ApproachSpace.transform(rect))
    }
}

/// The runway's centre line, the capsule at its threshold.
struct RunwayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: 742, y: 150))
        p.addLine(to: CGPoint(x: 792, y: 150))
        return p.applying(ApproachSpace.transform(rect))
    }
}

/// The approach profile: four waypoints down the slope, a figure under each, and the approach lights toward the runway.
/// A review that stopped pulls up on a dashed go-around. A filter skip never gets here (the sheet hides it).
struct ApproachView: View {
    @ObservedObject var flight: FlightModel
    let reached: Int
    let landed: Bool
    let figures: [FigureText]
    let settled: Bool
    let signal: Color
    let onPick: (FlightReadout) -> Void

    static let height = ApproachSpace.height
    private static let names = ["GATHER", "REVIEW", "CHECK", "LAND"]

    /// The draw-in: 1.15 s for a landed review, 0.5 s when it stopped.
    private var duration: Double { landed ? 1.15 : 0.5 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .topLeading) {
                ApproachGuide()
                    .stroke(Gotham.edge, style: StrokeStyle(lineWidth: 1, dash: [2, 5]))
                lights(w)
                RunwayShape()
                    .stroke(Gotham.fg.opacity(0.9), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                SlopeShape(reached: reached, landed: landed)
                    .trim(from: 0, to: settled ? 1 : flight.draw)
                    .stroke(Gotham.fg, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .animation(.timingCurve(0.2, 0.7, 0.1, 1, duration: duration), value: flight.draw)
                if !landed {
                    GoAroundShape()
                        .stroke(signal, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 5]))
                        .opacity(settled || flight.goAround ? 1 : 0)
                        .animation(.easeOut(duration: 0.5), value: flight.goAround)
                }
                halo(w)
                ForEach(0..<4, id: \.self) { i in
                    column(i, w)
                }
                ForEach(0..<4, id: \.self) { i in
                    waypoint(i, w)
                }
            }
            .frame(width: w, height: Self.height, alignment: .topLeading)
        }
        .frame(height: Self.height)
    }

    // MARK: Pieces

    private func point(_ i: Int, _ w: CGFloat) -> CGPoint {
        let p = ApproachSpace.point(i, landed: landed)
        return CGPoint(x: p.x * w / ApproachSpace.width, y: p.y)
    }

    /// The last reached stage: where the flight ends.
    private var last: Int { reached - 1 }

    private func fill(_ i: Int) -> Color {
        if i == last { return landed ? signal : Gotham.mat }
        return i < reached ? Gotham.fg : Gotham.mat
    }

    private func stroke(_ i: Int) -> Color {
        if i == last { return signal }
        return i < reached ? Gotham.fg : FlightText.faint
    }

    /// Each waypoint fades in as the slope passes it.
    private func delay(_ i: Int) -> Double {
        Double(min(i, last)) * duration / Double(max(reached, 2)) + 0.08
    }

    private func target(_ i: Int) -> FlightReadout {
        landed ? [.blast, .review, .checker, .review][i] : [.gathered, .review, .review, .notes][i]
    }

    private func waypoint(_ i: Int, _ w: CGFloat) -> some View {
        let hot = flight.hot == i
        return Circle()
            .fill(fill(i))
            .overlay(Circle().strokeBorder(stroke(i), lineWidth: 1.5))
            .frame(width: 10, height: 10)
            .scaleEffect(hot ? 1.4 : 1)
            .animation(.easeOut(duration: 0.3), value: hot)
            .frame(width: 20, height: 20)
            .contentShape(Circle())
            .opacity(settled || flight.waypoints ? 1 : 0)
            .animation(.easeOut(duration: 0.35).delay(delay(i)), value: flight.waypoints)
            .onHover { inside in
                if inside {
                    flight.hot = i
                } else if flight.hot == i {
                    flight.hot = nil
                }
            }
            .onTapGesture { onPick(target(i)) }
            .position(point(i, w))
    }

    /// The touchdown halo: a ring around the last reached waypoint that grows from 6 pt to 22 pt and fades.
    private func halo(_ w: CGFloat) -> some View {
        Circle()
            .stroke(signal, lineWidth: 1)
            .frame(width: 12, height: 12)
            .scaleEffect(1 + (22.0 / 6.0 - 1) * flight.halo)
            .opacity(!settled && flight.fired ? 0.9 * (1 - Double(flight.halo)) : 0)
            .position(point(last, w))
    }

    /// One stage's label and figure. Stages the review never reached are dimmed; the Land figure is always drawn.
    private func column(_ i: Int, _ w: CGFloat) -> some View {
        let end = landed && i == 3
        let at = point(i, w)
        let figure = figures[i]
        let dim = i >= reached && i != 3
        let on = flight.hot == i
        let x = end ? w - 180 : at.x - 6
        let shown = settled || flight.figures
        return ZStack(alignment: .topLeading) {
            Text(Self.names[i])
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(on ? Gotham.fg : Gotham.mute)
                .frame(width: 180, alignment: end ? .trailing : .leading)
                .offset(x: x, y: at.y - 26)
            VStack(alignment: end ? .trailing : .leading, spacing: 2) {
                Text(figure.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Gotham.fg)
                    .multilineTextAlignment(end ? .trailing : .leading)
                if let sub = figure.sub {
                    Text(sub)
                        .font(.system(size: 12))
                        .foregroundStyle(on ? Gotham.fg : Gotham.mute)
                        .multilineTextAlignment(end ? .trailing : .leading)
                }
            }
            .frame(width: 180, alignment: end ? .trailing : .leading)
            .offset(x: x, y: at.y + 14)
        }
        .allowsHitTesting(false)
        .frame(width: w, height: Self.height, alignment: .topLeading)
        .opacity(shown ? 1 : 0)
        .offset(y: shown ? 0 : -6)
        .animation(.timingCurve(0.2, 0.7, 0.1, 1, duration: 0.6).delay(0.12 + 0.06 * Double(i)), value: flight.figures)
        .opacity(dim ? 0.38 : 1)
    }

    // MARK: Approach lights

    @ViewBuilder
    private func lights(_ w: CGFloat) -> some View {
        if settled {
            ForEach(0..<7, id: \.self) { k in
                light(k, w, lit: false)
            }
        } else {
            // One light at a time, 140 ms apart, walking toward the runway.
            TimelineView(.periodic(from: .now, by: 0.14)) { context in
                let lit = Int(context.date.timeIntervalSinceReferenceDate / 0.14) % 10
                ForEach(0..<7, id: \.self) { k in
                    light(k, w, lit: lit == k)
                }
            }
        }
    }

    private func light(_ k: Int, _ w: CGFloat, lit: Bool) -> some View {
        let x = 560 + CGFloat(k) / 7 * 175
        let y = 40 + (x - 8) / 784 * 96
        return Circle()
            .fill(Gotham.fg)
            .frame(width: 3.2, height: 3.2)
            .opacity(lit ? 0.55 : 0.08)
            .position(x: x * w / ApproachSpace.width, y: y)
    }
}

/// The review for a tapped card, as a sheet: the flight recorder over the review. Done closes it, and Esc too.
/// `fixture` is snapshot rendering's stand-in for the artifacts the sheet would read from disk.
struct ReviewSheet: View {
    let row: ReviewRow
    let text: ReviewTextRecord?
    @ObservedObject var store: Store
    let onClose: () -> Void
    @StateObject private var artifacts: RunArtifactsModel

    init(row: ReviewRow, text: ReviewTextRecord?, store: Store, fixture: RunArtifacts? = nil,
         onClose: @escaping () -> Void) {
        self.row = row
        self.text = text
        self.store = store
        self.onClose = onClose
        _artifacts = StateObject(wrappedValue: RunArtifactsModel(fixture: fixture))
    }

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
            .padding(.horizontal, 18)
            .padding(.top, 14)
            ReviewDetail(row: row, text: text, store: store, artifacts: artifacts, onClose: onClose)
        }
        .frame(width: 860, height: 760)
        .background(Gotham.void)
    }
}

/// The sheet's body: header, approach, verdict bar, readouts and footer. Every action (post, discard, review anyway,
/// review again, copy, open on GitHub) lives here, with its confirm.
struct ReviewDetail: View {
    let row: ReviewRow
    /// What the review said, read for this row. Nil for reviews from before 1.2.
    let text: ReviewTextRecord?
    @ObservedObject var store: Store
    @ObservedObject var artifacts: RunArtifactsModel
    let onClose: () -> Void
    @StateObject private var flight = FlightModel()
    @AppStorage("motion") private var motion = "full"
    @AppStorage("signalColour") private var signalKey = "amber"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.offscreenRender) private var offscreen
    @Environment(\.colorScheme) private var scheme

    private var p: Palette { Palette(scheme) }
    private var strip: Strip { row.strip }
    private var signal: Color { Gotham.signal(signalKey) }
    /// Snapshots and reduced motion draw the settled sheet.
    private var settled: Bool { offscreen || Motion.reduced(reduceMotion) }
    private var art: RunArtifacts? { artifacts.artifacts }

    /// A held draft or a verdict: the run got through the review.
    private var landed: Bool { row.draft || row.verdict == .approve || row.verdict == .changes }
    /// A skip with no scratch folder, no tokens, from the gather stage: the filter skipped it before any work.
    private var filtered: Bool {
        row.verdict == .skipped && row.stage == .gather && row.tokens == 0 && art?.folder == nil
    }
    /// A session skip: the run did some work, then skipped the PR.
    private var sessionSkip: Bool { row.verdict == .skipped && !filtered && !row.tooLarge }
    private var reviewAgainOffered: Bool {
        !row.draft && !row.tooLarge && (row.verdict == nil || sessionSkip)
    }
    /// The stages reached, 1 to 4: gather, review, check, post. A landed review reached all four.
    private var reached: Int { landed ? 4 : row.stage.rank + 1 }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                WinScroll {
                    content(proxy)
                }
            }
            .frame(maxHeight: .infinity)
            footer
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .padding(.bottom, 22)
        }
        .onAppear {
            artifacts.load(folder: RunArtifacts.folder(store.paths, runId: row.runId, slug: row.repo, n: row.number))
            if !settled { flight.play(duration: landed ? 1.15 : 0.5) }
        }
        .onReceive(WindowRouter.shared.$pending.compactMap { $0 }.receive(on: DispatchQueue.main)) { _ in
            takeReviewAction()
        }
    }

    private func content(_ proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !filtered {
                ApproachView(flight: flight, reached: reached, landed: landed, figures: figures,
                                settled: settled, signal: signal) { readout in
                    proxy.scrollTo(readout, anchor: .center)
                    flight.flash(readout)
                }
                .padding(.top, 26)
                .padding(.horizontal, -8)
            }
            verdictBar
                .padding(.top, 6)
            if let error = store.draftErrors[row.stripID] {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(p.error)
                    .padding(.top, WinMetrics.s8)
            }
            readouts
                .padding(.top, 30)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.top, 22)
    }

    // MARK: Header

    private var crumb: String {
        var parts = ["\(row.repo) · #\(row.number)"]
        if let author = row.author { parts.append(author) }
        return parts.joined(separator: " · ")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AvatarView(login: row.author ?? "pr", size: 18)
                Text(crumb)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
            }
            Text(row.title ?? "#\(row.number)")
                .font(.system(size: 26, weight: .bold))
                .tracking(-0.5)
                .foregroundStyle(Gotham.fg)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if !metaItems.isEmpty {
                HStack(spacing: 18) {
                    ForEach(Array(metaItems.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(item.value)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Gotham.fg)
                            if !item.label.isEmpty {
                                Text(item.label)
                                    .foregroundStyle(Gotham.mute)
                            }
                        }
                    }
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .padding(.top, 10)
            }
        }
    }

    /// Head, size, files, tokens and duration, each only when known. Size comes from the artifacts, else the PR's
    /// changed lines.
    private var metaItems: [(value: String, label: String)] {
        var out: [(value: String, label: String)] = []
        if let head = art?.headSha ?? row.head { out.append((String(head.prefix(7)), "head")) }
        if let added = art?.additions, let removed = art?.deletions {
            out.append(("+\(added.formatted()) −\(removed.formatted())", ""))
        } else if let lines = row.changedLines {
            out.append((lines.formatted(), "lines changed"))
        }
        if let files = art?.fileCount { out.append((files == 100 ? "100+" : "\(files)", "files")) }
        if row.tokens > 0 { out.append((compactTokens(row.tokens), "tokens")) }
        if let duration = row.duration, row.verdict != .skipped {
            out.append((Self.duration(duration), ""))
        }
        if row.flagged { out.append(("Touches", flaggedPaths)) }
        return out
    }

    /// The repo's flagged paths, as configured (`infra/, .github/workflows/`).
    private var flaggedPaths: String {
        let paths = store.snap.config?.repos.first { $0.slug == row.repo }?.flagPaths ?? []
        return paths.isEmpty ? "flagged paths" : paths.joined(separator: ", ")
    }

    // MARK: Approach figures

    /// The four figures under the approach, from the row and its artifacts. Before the artifacts load, the figures wait.
    private var figures: [FigureText] {
        [gatherFigure, reviewFigure, checkFigure, landFigure]
    }

    private var gatherFigure: FigureText {
        guard artifacts.loaded else { return FigureText(title: "—", sub: nil) }
        guard let a = art, a.folder != nil else {
            return FigureText(title: "—", sub: "Details are kept for 7 days.")
        }
        let counts = [a.fileCount.map { $0 == 100 ? "100+ files" : "\($0) files" },
                      a.commentCount.map { "\($0) comments" }].compactMap { $0 }
        var sub: [String] = []
        if a.diffParts > 0 { sub.append("Diff split into \(a.diffParts) parts.") }
        if let blast = a.blast {
            switch RunArtifacts.blastSummary(blast).chip {
            case "GitNexus": sub.append("Callers from GitNexus.")
            case "grep only · partial": sub.append("Callers from grep, partial.")
            case "not run": sub.append("Blast radius not run.")
            default: break
            }
        }
        return FigureText(title: counts.isEmpty ? "—" : counts.joined(separator: " · "),
                          sub: sub.isEmpty ? nil : sub.joined(separator: " "))
    }

    private var reviewFigure: FigureText {
        if reached < 2 { return FigureText(title: "Not reached", sub: nil) }
        guard artifacts.loaded, let a = art, a.folder != nil else { return FigureText(title: "—", sub: nil) }
        guard let draft = a.draft else { return FigureText(title: "No review", sub: nil) }
        let count = draft.comments.count
        guard let verdict = draft.verdict else { return FigureText(title: "No verdict", sub: "First pass") }
        let word = verdict == .changes ? "Changes" : "Approve"
        return FigureText(title: "\(word) · \(count) finding\(count == 1 ? "" : "s")", sub: "First pass")
    }

    private var checkFigure: FigureText {
        if reached < 3 { return FigureText(title: "Not reached", sub: nil) }
        guard artifacts.loaded, let a = art, a.folder != nil, let final = a.final else {
            return FigureText(title: "—", sub: nil)
        }
        let delta = CheckerDelta.compute(drafts: a.drafts, final: final)
        var title = "\(delta.kept.count) kept"
        if !delta.added.isEmpty { title += " · \(delta.added.count) added" }
        if !delta.dropped.isEmpty { title += " · \(delta.dropped.count) dropped" }
        return FigureText(title: title, sub: "Every quoted line re-opened")
    }

    private var landFigure: FigureText {
        if row.draft { return FigureText(title: "Held as draft", sub: "Waiting for you to post") }
        switch row.verdict {
        case .skipped?: return FigureText(title: "Skipped", sub: row.reason)
        case nil: return FigureText(title: "No result", sub: "Nothing posted")
        case .approve?, .changes?:
            if let postedAt = row.postedAt {
                return FigureText(title: "Posted", sub: "at \(HeaderCopy.clock(postedAt))")
            }
            return FigureText(title: row.verdict == .approve ? "Approved" : "Posted", sub: nil)
        }
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

    /// The reason (for a verdict) and the draft or posted state, joined. Legacy rows have no record, so they say nothing.
    private var subtitle: String? {
        var parts: [String] = []
        if !row.tooLarge, row.verdict == .changes || row.verdict == .approve, let reason = row.reason {
            parts.append(reason)
        }
        if row.draft {
            parts.append("Waiting for you")
        } else if row.postedAt != nil {
            parts.append("Posted")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
            // The verdict keeps its full width on one line; the subtitle gives way first when the bar is narrow.
            Text(verdictWord)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(barInk)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            if let subtitle {
                Text(subtitle)
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
        } else if reviewAgainOffered {
            WinButton(title: "Review again", style: .primary, small: true) { reviewAgain() }
                .disabled(store.snap.running || store.snap.dryRunning)
        }
    }

    /// Runs the PR's review again by hand, after the usual confirm. The sheet closes once the review starts.
    private func reviewAgain() {
        guard Confirm.review(store, .prs([PRRef(slug: row.repo, n: row.number)])) else { return }
        onClose()
    }

    // MARK: Readouts

    @ViewBuilder
    private var readouts: some View {
        if landed {
            reviewReadout
            checkerReadout
            blastReadout
            notesReadout
        } else {
            notesReadout
            gatheredReadout
            blastReadout
            reviewReadout
        }
    }

    @ViewBuilder
    private var reviewReadout: some View {
        if !filtered || row.tooLarge {
            readout(.review, "Review", landed ? "Final text" : nil) {
                if row.tooLarge {
                    note("Too large: \((row.changedLines ?? 0).formatted()) lines, limit \(store.snap.maxChangedLines)")
                } else if !landed {
                    note(row.verdict == .skipped ? "Nothing reviewed. The session skipped it." : stoppedWords)
                } else if let text {
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(Array(Self.paragraphs(text.body).enumerated()), id: \.offset) { _, paragraph in
                            prose(paragraph)
                        }
                    }
                    ForEach(Array(text.comments.enumerated()), id: \.offset) { _, comment in
                        commentCard(comment)
                    }
                } else {
                    note("Review text not recorded (before 1.2)")
                }
            }
        }
    }

    /// Where a review that stopped without a verdict got to.
    private var stoppedWords: String {
        let phase = ["after gathering", "during review", "during check", "before posting"][min(max(reached, 1), 4) - 1]
        return "Nothing reviewed. The session stopped \(phase)."
    }

    @ViewBuilder
    private var checkerReadout: some View {
        if landed, let a = art, let final = a.final {
            let delta = CheckerDelta.compute(drafts: a.drafts, final: final)
            readout(.checker, "Checker", "Draft to final") {
                HStack(spacing: 22) {
                    tally("\(delta.kept.count)", "kept", Gotham.fg)
                    tally("\(delta.added.count)", "added", signal)
                    tally("\(delta.dropped.count)", "dropped", Gotham.fg)
                }
                .padding(.bottom, 12)
                let findings: [(tag: String, comment: RunArtifacts.Comment, tint: Color, dropped: Bool)] =
                    delta.added.map { ("ADDED", $0, signal, false) }
                    + delta.kept.map { ("KEPT", $0, Gotham.mute, false) }
                    + delta.dropped.map { ("DROPPED", $0, FlightText.faint, true) }
                ForEach(Array(findings.enumerated()), id: \.offset) { index, item in
                    finding(item.tag, item.comment, tint: item.tint, dropped: item.dropped, first: index == 0)
                }
                if delta.bodyChanged {
                    Text("Body tightened by the checker.")
                        .font(.system(size: 13))
                        .foregroundStyle(Gotham.mute)
                        .padding(.top, 10)
                }
            }
        }
    }

    @ViewBuilder
    private var blastReadout: some View {
        if let blast = art?.blast {
            let summary = RunArtifacts.blastSummary(blast)
            if !summary.chip.isEmpty || !summary.bullets.isEmpty {
                readout(.blast, "Blast radius", "What else it touches") {
                    if !summary.chip.isEmpty {
                        chip(summary.chip, warn: summary.partial)
                    }
                    bullets(summary.bullets)
                }
            }
        }
    }

    @ViewBuilder
    private var notesReadout: some View {
        if let notes = art?.notes, !notes.isEmpty {
            readout(.notes, "Session notes", landed ? "From the run" : "Why it stopped") {
                bullets(notes)
            }
        }
    }

    @ViewBuilder
    private var gatheredReadout: some View {
        let items = gatheredItems
        if !items.isEmpty {
            readout(.gathered, "Gathered", "Before it stopped") {
                bullets(items)
            }
        }
    }

    private var gatheredItems: [String] {
        guard let a = art else { return [] }
        var out: [String] = []
        if a.headSha != nil || a.fileCount != nil {
            var line = "PR info"
            if let head = a.headSha { line += " at head `\(head.prefix(7))`" }
            if let files = a.fileCount { line += ", \(files == 100 ? "100+" : "\(files)") files" }
            out.append(line + ".")
        }
        if a.commentCount != nil {
            out.append("Threads: \(a.reviewCount ?? 0) reviews, \(a.reviewCommentCount ?? 0) review comments, "
                       + "\(a.issueCommentCount ?? 0) comments.")
        }
        return out
    }

    /// One readout: a 132 pt label column, then its content, under a hairline. Flashes when a waypoint jumps to it.
    private func readout<Inner: View>(_ id: FlightReadout, _ title: String, _ sub: String?,
                                      @ViewBuilder _ inner: () -> Inner) -> some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(Gotham.mute)
                if let sub {
                    Text(sub)
                        .font(.system(size: 11))
                        .foregroundStyle(FlightText.faint)
                }
            }
            .frame(width: 132, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                inner()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(Gotham.edge).frame(height: 1)
        }
        .background {
            Rectangle()
                .fill(LinearGradient(colors: [Color.white.opacity(0.03), .clear], startPoint: .leading,
                                     endPoint: .trailing))
                .opacity(flight.flashed == id ? 1 : 0)
                .animation(.easeOut(duration: 0.3), value: flight.flashed == id)
        }
        .id(id)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .lineSpacing(7)
            .foregroundStyle(Gotham.mute)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 600, alignment: .leading)
    }

    private func prose(_ text: String) -> some View {
        Text(FlightText.styled(text))
            .font(.system(size: 13))
            .lineSpacing(7)
            .foregroundStyle(Gotham.mute)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: 600, alignment: .leading)
    }

    private func bullets(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(FlightText.styled(item))
                    .font(.system(size: 13))
                    .lineSpacing(5)
                    .foregroundStyle(Gotham.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 16)
                    .overlay(alignment: .topLeading) {
                        Rectangle().fill(FlightText.faint).frame(width: 5, height: 1).offset(x: 2, y: 9)
                    }
            }
        }
        .frame(maxWidth: 600, alignment: .leading)
    }

    private func chip(_ text: String, warn: Bool) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(warn ? signal : Gotham.fg)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(warn ? signal.opacity(0.5) : Gotham.hi, lineWidth: 1))
            .padding(.bottom, 10)
    }

    private func tally(_ value: String, _ label: String, _ colour: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .light))
                .tracking(-0.4)
                .monospacedDigit()
                .foregroundStyle(colour)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
        }
    }

    /// One checker finding: its tag, the place in mono blue, and its first sentence. Dropped findings are struck through.
    private func finding(_ tag: String, _ comment: RunArtifacts.Comment, tint: Color, dropped: Bool, first: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(tag)
                .font(.system(size: 10, weight: .bold))
                .tracking(1.0)
                .foregroundStyle(tint)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "\(comment.path):\(comment.line)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(FlightText.loc)
                Text(FlightText.styled(FlightText.firstSentence(comment.body)))
                    .font(.system(size: 12.5))
                    .lineSpacing(4)
                    .foregroundStyle(dropped ? FlightText.faint : Gotham.mute)
                    .strikethrough(dropped, color: FlightText.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 9)
        .frame(maxWidth: 600, alignment: .leading)
        .overlay(alignment: .top) {
            if !first {
                Rectangle().fill(Gotham.edge).frame(height: 1)
            }
        }
    }

    /// One inline comment: its place in mono blue, then the text.
    private func commentCard(_ comment: PayloadComment) -> some View {
        VStack(alignment: .leading, spacing: WinMetrics.s4) {
            Text(verbatim: "\(comment.path):\(comment.line)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(FlightText.loc)
            Text(FlightText.styled(comment.body))
                .font(.system(size: 13))
                .lineSpacing(4)
                .foregroundStyle(Gotham.fg)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, WinMetrics.s12)
        .padding(.horizontal, WinMetrics.s16)
        .frame(maxWidth: 600, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Gotham.row))
        .padding(.top, WinMetrics.s12)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: WinMetrics.s16) {
            Text(footerWords)
            Spacer(minLength: 0)
            if let folder = art?.folder {
                WinButton(title: "Show files in Finder", style: .link) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: folder)])
                }
            }
            if RepoConfig.isValidSlug(row.repo) {
                WinButton(title: "Open on GitHub", style: .link) { openOnGitHub() }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(Gotham.mute)
        .monospacedDigit()
    }

    /// "3 min 12 s · 427k tokens", each part only when known.
    private var footerWords: String {
        var parts: [String] = []
        if row.verdict != .skipped, let duration = row.duration { parts.append(Self.duration(duration)) }
        if row.tokens > 0 { parts.append("\(compactTokens(row.tokens)) tokens") }
        return parts.joined(separator: " · ")
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
