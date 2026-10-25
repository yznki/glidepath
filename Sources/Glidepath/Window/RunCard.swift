import SwiftUI

/// The folds a run card can open. Each card keeps its own, all collapsed by default.
final class RunFolds: ObservableObject {
    enum Fold: Hashable { case more, already, skipped }

    @Published var open: Set<Fold> = []

    func toggle(_ fold: Fold) {
        if open.contains(fold) { open.remove(fold) } else { open.insert(fold) }
    }
}

/// One run as a card (prototype `.run`): its title and meta, the digest sentence, a bar while it runs, and its rows.
/// Now shows the newest runs with it, and History every run. A reviewed row opens its flight recorder through `open`,
/// given the PR's `Strip.id`. A stopped row offers Review again.
struct RunCard: View {
    let run: RunState
    /// Whether this run is the one going now.
    let running: Bool
    @ObservedObject var store: Store
    let open: (String) -> Void

    @StateObject private var folds = RunFolds()
    @AppStorage("signalColour") private var signalKey = "amber"

    private var signal: Color { Gotham.signal(signalKey) }

    var body: some View {
        let digest = RunDigest(run: run, running: running)
        VStack(alignment: .leading, spacing: 0) {
            header
            sentence(digest)
            if running { progress(digest) }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(digest.inFlight, id: \.stripID) { row in inFlightRow(row) }
                reviewedRows(digest)
                ForEach(digest.stopped, id: \.stripID) { row in stoppedRow(row) }
                skippedFolds(digest)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)
        }
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Gotham.mat))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.bottom, 12)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(RunDigest.title(for: run))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Gotham.fg)
            Spacer(minLength: 8)
            if running {
                Text(liveMeta)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .monospacedDigit()
                Button("Stop") { Confirm.stop(store) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Gotham.mute)
            } else {
                Text(finishedMeta)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    /// "started 4:30 PM · 188k tokens", the tokens counting the session in flight.
    private var liveMeta: String {
        "started \(HeaderCopy.clock(run.started)) · \(compactTokens(run.tokens + store.liveTokens.total)) tokens"
    }

    /// "4:30 PM · 14 min · 1.7M tokens".
    private var finishedMeta: String {
        var parts = [HeaderCopy.clock(run.started)]
        if let finished = run.finished {
            let s = Int(finished.timeIntervalSince(run.started))
            parts.append(s < 60 ? "\(s) s" : "\(s / 60) min")
        }
        parts.append("\(compactTokens(run.tokens)) tokens")
        return parts.joined(separator: " · ")
    }

    // MARK: Sentence and bar

    private func sentence(_ d: RunDigest) -> some View {
        (Text(d.lead)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(d.failed != nil ? signal : Gotham.fg)
         + Text(d.rest.isEmpty ? "" : " " + d.rest)
            .font(.system(size: 13))
            .foregroundStyle(Gotham.mute))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
    }

    /// Done over to review, as a 2 pt bar.
    private func progress(_ d: RunDigest) -> some View {
        let fraction = d.toReview == 0 ? 0 : Double(d.done) / Double(d.toReview)
        return GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Gotham.edge)
                Capsule().fill(Gotham.fg).frame(width: geo.size.width * fraction)
            }
        }
        .frame(height: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: Rows

    private func inFlightRow(_ row: RunDigest.Row) -> some View {
        line(row, sub: Text(verbatim: "\(row.slug) #\(String(row.pr.n))")) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    if i < row.pr.stage.rank {
                        Circle().fill(Gotham.fg).frame(width: 7, height: 7)
                    } else if i == row.pr.stage.rank {
                        Pulse(colour: Gotham.fg, period: 1.4)
                    } else {
                        Circle().strokeBorder(Gotham.mute, lineWidth: 1.5).frame(width: 7, height: 7)
                    }
                }
                Text(Self.stageWord(row.pr.stage))
                    .font(.system(size: 11))
                    .foregroundStyle(Gotham.mute)
                    .padding(.leading, 6)
            }
        }
    }

    /// The first five reviewed rows, then a fold for the rest.
    @ViewBuilder
    private func reviewedRows(_ d: RunDigest) -> some View {
        let expanded = folds.open.contains(.more)
        let shown = expanded ? d.reviewed : Array(d.reviewed.prefix(5))
        ForEach(shown, id: \.stripID) { row in reviewedRow(row) }
        if d.reviewed.count > 5 {
            fold(.more, expanded ? "Show fewer" : "\(d.reviewed.count - 5) more reviewed")
        }
    }

    /// "held" for a draft, "posted" when the review is on GitHub, else "not posted". A repo that posts reviews
    /// directly counts as posted: the run wrote the review itself.
    private func reviewedRow(_ row: RunDigest.Row) -> some View {
        let verdict = row.pr.verdict == .changes ? "Changes" : "Approved"
        let colour = row.pr.verdict == .changes ? signal : Gotham.fg
        let postsDirectly = store.snap.config?.repos.first { $0.slug == row.slug }?.posting == .review
        let state = row.pr.draft == true ? "held" : (row.pr.posted != nil || postsDirectly) ? "posted" : "not posted"
        var sub = Text(verdict).foregroundStyle(colour).fontWeight(.semibold)
        if let reason = PRFilter.displayReason(row.pr.reason) { sub = sub + Text(" · \(reason)") }
        sub = sub + Text(verbatim: " · #\(String(row.pr.n))")
        return Button { open(row.stripID) } label: {
            line(row, sub: sub) {
                Text(state)
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
            }
        }
        .buttonStyle(.plain)
    }

    /// A PR the run stopped before a verdict. Review again goes through the same confirm as the Review menu. A
    /// failed attempt shows its error under the row.
    private func stoppedRow(_ row: RunDigest.Row) -> some View {
        let strip = Strip(repo: row.slug, number: row.pr.n, author: row.pr.author, title: row.pr.title,
                          reason: row.pr.reason, stage: row.pr.stage.rank + 1, active: false, verdict: nil,
                          tokens: row.pr.tokens, skipReason: row.pr.skipReason, changedLines: row.pr.changedLines)
        let sub = Text("Stopped in \(Self.stageWord(row.pr.stage).lowercased())")
            .foregroundStyle(Gotham.mute)
            + Text(verbatim: " · no result · #\(String(row.pr.n))")
        return VStack(alignment: .leading, spacing: 4) {
            line(row, sub: sub) {
                WinButton(title: "Review again", style: .outline, small: true) {
                    Confirm.review(store, .prs([PRRef(slug: row.slug, n: row.pr.n)]))
                }
                .disabled(store.snap.running)
            }
            if let error = store.draftErrors[strip.id] {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(signal)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    /// "N already reviewed by you" with the PR numbers, then "N skipped" with the other groups.
    @ViewBuilder
    private func skippedFolds(_ d: RunDigest) -> some View {
        let already = d.skipped[.alreadyReviewed] ?? []
        if !already.isEmpty {
            fold(.already, "\(already.count) already reviewed by you", chips: already.map { "#\(String($0.pr.n))" })
        }
        let groups = RunDigest.SkipKind.allCases.filter { $0 != .alreadyReviewed }.compactMap { kind -> (RunDigest.SkipKind, [RunDigest.Row])? in
            guard let rows = d.skipped[kind], !rows.isEmpty else { return nil }
            return (kind, rows)
        }
        let count = groups.reduce(0) { $0 + $1.1.count }
        if count > 0 {
            let chips = groups.map { kind, rows -> String in
                let text = kind == .own ? "\(rows.count) your own" : RunDigest.groupText(kind, rows.count)
                return rows.count == 1 ? "\(text) · #\(String(rows[0].pr.n))" : text
            }
            fold(.skipped, "\(count) skipped", chips: chips)
        }
    }

    // MARK: Shared parts

    /// One row: the avatar, the title over a muted line, and a trailing part. Tapping it is the caller's `Button`.
    private func line<Trailing: View>(_ row: RunDigest.Row, sub: Text, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            AvatarView(login: row.pr.author ?? "pr", size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.pr.title ?? "#\(row.pr.n)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                sub
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    /// A fold row that opens a list of chips, or a set of rows for "more reviewed".
    private func fold(_ fold: RunFolds.Fold, _ label: String, chips: [String] = []) -> some View {
        let open = folds.open.contains(fold)
        return VStack(alignment: .leading, spacing: 0) {
            Button { folds.toggle(fold) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Text(label)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open && !chips.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 6, alignment: .leading)],
                          alignment: .leading, spacing: 6) {
                    ForEach(chips, id: \.self) { chip in
                        Text(verbatim: chip)
                            .font(.system(size: 11))
                            .foregroundStyle(Gotham.mute)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Gotham.row))
                            .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 10)
            }
        }
    }

    static func stageWord(_ stage: Stage) -> String {
        switch stage {
        case .gather: return "Gathering"
        case .review: return "Reviewing"
        case .check: return "Checking"
        case .post: return "Posting"
        }
    }
}
