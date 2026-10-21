import SwiftUI
import ServiceManagement
import AppKit

private let stateSpring = Animation.spring(response: 0.45, dampingFraction: 0.86)
private let stageWords = ["starting", "gathering", "reviewing", "checking", "posting"]
private let rowMaxVisible: CGFloat = 6 * 64

/// View-local state. `@State` is a macro in the SDK and Command Line Tools cannot load its plugin,
/// so views keep their few mutable values in this object instead.
final class LocalState: ObservableObject {
    @Published var loginOn = false
    @Published var rowsHeight: CGFloat = 0
    @Published var hovering = false
    @Published var scale: CGFloat = 1.3
}

private struct RowsHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// "1.2k", "84k", "3.1M". Token counts in the header and strips.
func compactTokens(_ n: Int) -> String {
    switch n {
    case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
    case 1_000...: return String(format: "%.0fk", Double(n) / 1_000)
    default: return "\(n)"
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    /// True only for `--snapshot` rendering: ImageRenderer draws ScrollView and AppKit-backed buttons blank.
    var offscreen = false
    @StateObject private var local = LocalState()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            if let line = lastSweepLine {
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }
            strips
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 360)
        .onAppear {
            guard !offscreen else { return }
            store.reload()
            local.loginOn = store.loginItemOn
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            RadarView(strips: store.strips, running: store.snap.running, size: 84)
                .frame(width: 84, height: 84)
            // Relative times ("in 2 h", "21 min") refresh every 30 s without a poll on the state.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    let copy = headerCopy(now: context.date)
                    Text(copy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(copy.amber ? Color.changes : .secondary)
                    if let big = copy.big {
                        Text(big)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    if let small = copy.small {
                        Text(small)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private struct HeaderCopy {
        var title: String
        var big: String?
        var small: String?
        var amber = false
    }

    private func headerCopy(now: Date) -> HeaderCopy {
        let snap = store.snap
        if !snap.jobInstalled {
            return HeaderCopy(title: "Schedule not installed", amber: true)
        }
        if snap.running {
            var small: String?
            if let started = snap.run?.started {
                let mins = max(0, Int(now.timeIntervalSince(started) / 60))
                small = "started \(Self.clock.string(from: started)) · \(mins) min"
                if let tokens = snap.run?.tokens, tokens > 0 { small? += " · \(compactTokens(tokens)) tokens" }
            }
            return HeaderCopy(title: "Reviewing", big: "\(store.done) of \(store.strips.count) done", small: small)
        }
        if snap.paused {
            return HeaderCopy(title: "Paused", big: nil, small: "scheduled runs skipped until resume")
        }
        guard snap.run != nil else {
            return HeaderCopy(title: "No sweeps yet")
        }
        var big: String?
        var small: String?
        if let next = snap.nextRun {
            big = "Next sweep \(Self.clock.string(from: next))"
            let mins = max(0, Int(next.timeIntervalSince(now) / 60))
            let h = mins / 60, m = mins % 60
            small = h > 0 ? "in \(h) h \(m) min" : "in \(m) min"
        }
        return HeaderCopy(title: "All quiet", big: big, small: small)
    }

    /// "Last sweep 10:04 · 1 approved · 4 changes · 3 skipped · 84k tokens", zero counts omitted.
    private var lastSweepLine: String? {
        guard store.snap.jobInstalled, !store.snap.running, let run = store.snap.run else { return nil }
        var parts = ["Last sweep \(Self.clock.string(from: run.started))"]
        let strips = store.strips
        let approved = strips.filter { $0.verdict == .approve }.count
        let changes = strips.filter { $0.verdict == .changes }.count
        let skipped = strips.filter { $0.verdict == .skipped }.count
        if approved > 0 { parts.append("\(approved) approved") }
        if changes > 0 { parts.append("\(changes) changes") }
        if skipped > 0 { parts.append("\(skipped) skipped") }
        if run.tokens > 0 { parts.append("\(compactTokens(run.tokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    // MARK: Strips

    @ViewBuilder
    private var strips: some View {
        if !store.snap.jobInstalled {
            VStack(alignment: .leading, spacing: 8) {
                Text("The scheduled job is not installed. Run:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("review-radar init")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else if store.snap.run == nil {
            Text("No PRs in the last sweep")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        } else if offscreen {
            rows
        } else {
            // Height follows the measured rows, capped at about six visible rows.
            ScrollView {
                rows
                    .background(GeometryReader { Color.clear.preference(key: RowsHeight.self, value: $0.size.height) })
            }
            .frame(height: min(max(local.rowsHeight, 1), rowMaxVisible))
            .onPreferenceChange(RowsHeight.self) { local.rowsHeight = $0 }
        }
    }

    /// Strips grouped under their repo, in config order.
    private var rows: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.snap.run?.repos ?? [], id: \.slug) { repo in
                VStack(alignment: .leading, spacing: 2) {
                    Text(repo.slug)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.top, 4)
                    if let error = repo.error {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(Color.changes)
                            .lineLimit(2)
                            .padding(.horizontal, 10)
                    }
                    let group = store.strips
                        .filter { $0.repo == repo.slug }
                        .sorted { ($0.active ? 0 : 1, -$0.number) < ($1.active ? 0 : 1, -$1.number) }
                    ForEach(group) { strip in
                        StripRow(strip: strip, runOver: !store.snap.running)
                    }
                }
            }
        }
        .padding(6)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let error = store.errorText {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(Color.changes)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            styled(HStack(spacing: 12) {
                Button(store.snap.running ? "Running" : "Run now") { confirmAndRun() }
                    .disabled(store.snap.running || !store.snap.jobInstalled)
                Button(store.snap.paused ? "Resume" : "Pause") { store.togglePause() }
                Button("Log") { NSWorkspace.shared.open(URL(fileURLWithPath: store.paths.logFile)) }
                if offscreen {
                    // ImageRenderer draws AppKit checkboxes as a prohibition sign; text stands in.
                    Text((store.loginItemOn ? "[x] " : "[ ] ") + "Open at login")
                } else {
                    Toggle("Open at login", isOn: Binding(
                        get: { local.loginOn },
                        set: { on in
                            store.setLoginItem(on)
                            local.loginOn = store.loginItemOn
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
                Spacer(minLength: 0)
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            })
            .controlSize(.small)
        }
    }

    /// Posting is public, so a run that can post reviews asks first.
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

    @ViewBuilder
    private func styled<V: View>(_ view: V) -> some View {
        if offscreen { view.buttonStyle(.plain) } else { view.buttonStyle(.borderless) }
    }

    static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

struct StripRow: View {
    let strip: Strip
    let runOver: Bool
    @StateObject private var local = LocalState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            if let url = URL(string: "https://github.com/\(strip.repo)/pull/\(strip.number)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "#\(strip.number)")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Fixed-width columns keep the rail at the same x on every row.
                Rail(stage: strip.stage, active: strip.active && strip.verdict == nil,
                     verdict: strip.verdict, reduceMotion: reduceMotion)
                    .frame(width: 64, height: 6)
                ZStack(alignment: .trailing) {
                    status
                }
                .frame(width: 96, alignment: .trailing)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(local.hovering ? 0.05 : 0))
            )
        }
        .buttonStyle(.plain)
        .onHover { local.hovering = $0 }
        .animation(stateSpring, value: local.hovering)
    }

    private var subtitle: String {
        var parts = [strip.author, strip.reason].compactMap { $0 }.filter { !$0.isEmpty }
        if strip.tokens > 0 { parts.append("\(compactTokens(strip.tokens)) tok") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var status: some View {
        if let verdict = strip.verdict {
            Stamp(verdict: verdict, key: "\(strip.id)-\(verdict.rawValue)", reduceMotion: reduceMotion)
        } else if strip.active {
            Text(stageWords[min(max(strip.stage, 0), 4)])
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.scan)
                .lineLimit(1)
        } else if runOver {
            Text("dropped")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct Rail: View {
    let stage: Int
    let active: Bool
    let verdict: Verdict?
    let reduceMotion: Bool

    var body: some View {
        let s = min(max(stage, 0), 4)
        HStack(spacing: 3) {
            if let verdict {
                // Stamped: every capsule takes the verdict color.
                ForEach(0..<4, id: \.self) { _ in
                    Capsule().fill(Self.color(verdict))
                }
            } else {
                // Active stage is the one in progress: stage 1 = segment 0. Done segments fill.
                let filledCount = active ? max(s - 1, 0) : s
                let activeIndex = active && s >= 1 ? s - 1 : -1
                ForEach(0..<4, id: \.self) { i in
                    if i == activeIndex {
                        ActiveSegment(reduceMotion: reduceMotion)
                    } else {
                        Capsule()
                            .fill(Color.primary.opacity(i < filledCount ? 0.35 : 0.1))
                    }
                }
            }
        }
    }

    static func color(_ verdict: Verdict) -> Color {
        switch verdict {
        case .approve: return Color.approve.opacity(0.55)
        case .changes: return Color.changes.opacity(0.55)
        case .skipped: return Color.secondary.opacity(0.25)
        }
    }
}

struct ActiveSegment: View {
    let reduceMotion: Bool

    var body: some View {
        if reduceMotion {
            Capsule().fill(Color.scan)
        } else {
            TimelineView(.animation) { context in
                let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                Capsule()
                    .fill(Color.scan.opacity(0.35))
                    .overlay {
                        GeometryReader { g in
                            Capsule()
                                .fill(LinearGradient(
                                    colors: [.clear, Color.scan, .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                .frame(width: g.size.width * 0.5)
                                .offset(x: g.size.width * 1.5 * phase - g.size.width * 0.5)
                        }
                        .clipShape(Capsule())
                    }
            }
        }
    }
}

struct Stamp: View {
    let verdict: Verdict
    let key: String
    let reduceMotion: Bool

    @StateObject private var local = LocalState()

    var body: some View {
        let (word, color): (String, Color) = {
            switch verdict {
            case .approve: return ("APPROVED", .approve)
            case .changes: return ("CHANGES", .changes)
            case .skipped: return ("SKIPPED", .secondary)
            }
        }()
        Text(word)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(color, lineWidth: 1.5)
            )
            .rotationEffect(.degrees(-4))
            .scaleEffect(reduceMotion ? 1 : local.scale)
            .id(key)
            .onAppear {
                if reduceMotion {
                    local.scale = 1
                } else {
                    withAnimation(stateSpring) { local.scale = 1 }
                }
            }
    }
}
