import SwiftUI
import AppKit

/// The faint ink of labels and empty values: Gotham has no token for it, and the chart uses the same level.
private let approachFaint = Color.white.opacity(0.22)

/// The Approach section: every PR tend works on, as a chart, with what needs the user and the tower's log. A PR's
/// drawer opens over the right side, with its gates, rounds, lessons and the hands-off switch.
struct ApproachSectionView: View {
    @ObservedObject var store: Store
    @StateObject private var model: ApproachModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("signalColour") private var signalKey = "amber"

    /// `opened` is the plane whose drawer is open at first draw: snapshot rendering only.
    init(store: Store, opened: String? = nil) {
        self.store = store
        _model = StateObject(wrappedValue: ApproachModel(opened: opened))
    }

    private var approach: ApproachSnapshot? { store.snap.approach }
    private var signal: Color { Gotham.signal(signalKey) }
    private var openedPlane: ApproachPlane? {
        guard let id = model.opened else { return nil }
        return approach?.planes.first { $0.id == id }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WinScroll {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    if store.snap.tendOn {
                        chartCard
                            .padding(.top, 18)
                        columns
                            .padding(.top, 8)
                    } else {
                        tendingOff
                            .padding(.top, 30)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, WinMetrics.titlebarZone)
                .padding(.bottom, 26)
            }
            if let plane = openedPlane {
                ApproachDrawer(plane: plane, store: store, model: model) { model.opened = nil }
                    .transition(.move(edge: .trailing))
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Motion.reduced(reduceMotion) ? .easeOut(duration: 0.15) : Motion.standard, value: model.opened)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Approach")
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.8)
                .foregroundStyle(Gotham.fg)
            Spacer(minLength: 8)
            if store.snap.tendOn {
                statusLine
                autopilotPill
            }
        }
    }

    /// What tend is doing now, or when it next looks. Reads the snapshot clock, so it moves with the day.
    private var statusLine: some View {
        SnapshotTimeline(schedule: .periodic(from: .now, by: 30)) { date in
            let text: String = {
                if let working = approach?.working { return working }
                if let next = approach?.nextLook { return "Next look in \(HeaderCopy.untilText(next, store.snap.now ?? date))" }
                return approach?.status ?? ""
            }()
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    /// The Autopilot pill: merges, replies and resolves without asking. Its switch writes `autopilot` to config.toml.
    private var autopilotPill: some View {
        let on = store.snap.config?.tend.autopilot ?? false
        return Button {
            model.setAutopilot(!on, store: store)
        } label: {
            HStack(spacing: 8) {
                MiniSwitch(isOn: on)
                Text("Autopilot")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Gotham.fg)
            }
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .frame(height: 28)
            .overlay(Capsule().strokeBorder(Gotham.hi, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Autopilot: merges, replies and resolves without asking. Hard stops still come to you.")
        .accessibilityValue(on ? "On" : "Off")
    }

    // MARK: Chart

    private var chartCard: some View {
        ZStack(alignment: .bottomLeading) {
            ApproachChart(planes: approach?.planes ?? [], onTap: { model.opened = $0 })
            legend
                .padding(.leading, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity)
        .background(
            RadialGradient(colors: [.white.opacity(0.05), .clear], center: UnitPoint(x: 0.92, y: 0.5),
                           startRadius: 0, endRadius: 420)
        )
        .background(Color(hex: "050507"))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem("Glidepath flying", Gotham.fg)
            legendItem("Needs you", signal)
            legendItem("Waiting on someone", Gotham.fg.opacity(0.4))
        }
        .font(.system(size: 11))
        .foregroundStyle(Color.white.opacity(0.22))
    }

    private func legendItem(_ text: String, _ colour: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(colour).frame(width: 8, height: 8)
            Text(text)
        }
    }

    // MARK: Columns

    private var columns: some View {
        HStack(alignment: .top, spacing: 28) {
            needs
                .frame(maxWidth: .infinity, alignment: .topLeading)
            tower
                .frame(width: 340, alignment: .topLeading)
        }
    }

    private var needs: some View {
        let items = approach?.needs ?? []
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                capLabel("Needs you")
                capLabel("\(items.count)", signal)
            }
            .padding(.bottom, 10)
            if items.isEmpty {
                Text("Nothing needs you")
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.mute)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 6) {
                    ForEach(items, id: \.id) { item in
                        TendNeedRow(item: item, url: store.approachPlane(item.slug, item.n)?.url ?? "", store: store)
                    }
                }
            }
        }
    }

    private var tower: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                capLabel("Tower")
                Spacer(minLength: 0)
                capLabel("live", approachFaint)
            }
            .padding(.bottom, 10)
            let lines = store.snap.tower
            if lines.isEmpty {
                Text("No rounds yet")
                    .font(.system(size: 13))
                    .foregroundStyle(Gotham.mute)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        towerLine(line)
                    }
                }
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Gotham.edge).frame(width: 1) }
            }
        }
    }

    private func towerLine(_ line: TowerLine) -> some View {
        let key = "\(Int(line.at.timeIntervalSince1970))#\(line.n)"
        let open = model.expanded.contains(key)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(HeaderCopy.clock(line.at))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(approachFaint)
                    .frame(width: 58, alignment: .leading)
                Text(line.text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(line.amber ? signal : Gotham.mute)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if open, let detail = line.detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Gotham.mute)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(hex: "0A0A0D")))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                    .padding(.leading, 68)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            model.toggle(key)
        }
    }

    // MARK: Tending off

    private var tendingOff: some View {
        VStack(spacing: 12) {
            Text("Tending is off")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Gotham.fg)
            Text("Glidepath reviews your teammates' PRs. Turn on tending to have it fix your own PRs' CI and replies.")
                .font(.system(size: 13))
                .foregroundStyle(Gotham.mute)
                .multilineTextAlignment(.center)
            SettingButton(title: "Turn on in Settings", prominent: true) {
                WindowRouter.shared.open(.settings)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

/// The popover's tend block, shown while tending is on: a mini approach chart, up to three holding items, and when tend
/// next looks. Empty otherwise.
struct ApproachPopoverBlock: View {
    @ObservedObject var store: Store
    let offscreen: Bool
    @AppStorage("signalColour") private var signalKey = "amber"

    var body: some View {
        if store.snap.tendOn, let approach = store.snap.approach {
            VStack(alignment: .leading, spacing: 0) {
                ApproachChart(planes: approach.planes, compact: true)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "060608"))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                ForEach(Array(approach.needs.prefix(3)), id: \.id) { item in
                    strip(item)
                }
                HStack(spacing: 8) {
                    Text(nextLook(approach))
                        .font(.system(size: 11.5))
                        .foregroundStyle(Gotham.mute)
                    Spacer(minLength: 0)
                    if offscreen {
                        Text("Open Approach").font(.system(size: 11.5)).foregroundStyle(Gotham.mute)
                    } else {
                        Button("Open Approach") { WindowRouter.shared.open(.approach) }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5))
                            .foregroundStyle(Gotham.mute)
                    }
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, StackGeometry.inset)
            .padding(.top, 12)
        }
    }

    private func strip(_ item: NeedsItem) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                Text(verbatim: "\(item.detail) · \(item.slug) #\(String(item.n))")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Gotham.mute)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if offscreen {
                Text("Open").font(.system(size: 12, weight: .semibold)).foregroundStyle(Gotham.fg)
            } else {
                SettingButton(title: "Open") { WindowRouter.shared.open(.approach) }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Gotham.signal(signalKey).opacity(0.07)))
        .padding(.top, 6)
    }

    /// "Next look in 3 min", or nothing when tend has not set one.
    private func nextLook(_ approach: ApproachSnapshot) -> String {
        guard let next = approach.nextLook else { return "" }
        return "Next look in \(HeaderCopy.untilText(next, store.snap.now ?? Date()))"
    }
}

/// The small switch in the Autopilot pill: 26 by 16, filled when on.
private struct MiniSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? Gotham.fg : Gotham.edge)
            Circle().fill(isOn ? Gotham.void : Color.white).frame(width: 12, height: 12).padding(2)
        }
        .frame(width: 26, height: 16)
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// A held fix or a stuck PR, with the action that clears it. Shared by Approach's Needs you and Now's.
struct TendNeedRow: View {
    let item: NeedsItem
    let url: String
    @ObservedObject var store: Store
    @AppStorage("signalColour") private var signalKey = "amber"

    private var signal: Color { Gotham.signal(signalKey) }
    private var held: Bool { item.kind == "held" }

    /// The detail split at its first " · ": the state, and the rest.
    private var lead: String {
        item.detail.components(separatedBy: " · ").first ?? item.detail
    }

    private var rest: String {
        let parts = item.detail.components(separatedBy: " · ")
        return parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : ""
    }

    var body: some View {
        HStack(spacing: 12) {
            Text("!")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(signal)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Gotham.row))
                .overlay(Circle().strokeBorder(signal.opacity(0.3), lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Gotham.fg)
                    .lineLimit(1)
                // The detail leads with its state ("Fix held", "Stuck"), which takes the signal colour.
                (Text(lead)
                    .foregroundStyle(signal)
                    .fontWeight(.semibold)
                 + Text(verbatim: rest + " · \(item.slug) #\(item.n)")
                    .foregroundStyle(Gotham.mute))
                    .font(.system(size: 12))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            actions
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(signal.opacity(0.07)))
    }

    @ViewBuilder
    private var actions: some View {
        if held {
            HStack(spacing: 8) {
                Button("Discard") { store.tendCommand(["discard", item.slug, "\(item.n)"]) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Gotham.mute)
                    .padding(.horizontal, 10)
                    .frame(height: 44)
                HoldButton(title: "Hold to push", doneTitle: "Pushing…", tint: signal) {
                    store.tendCommand(["push", item.slug, "\(item.n)"])
                }
                .id(item.id)
                .frame(width: 150)
            }
        } else {
            HStack(spacing: 8) {
                SettingButton(title: "Open PR") {
                    if let link = URL(string: url) { NSWorkspace.shared.open(link) }
                }
                SettingButton(title: "Try again", prominent: true) {
                    store.tendCommand(["retry", item.slug, "\(item.n)"])
                }
            }
        }
    }
}

/// The PR drawer: what the landing checklist says, today's rounds, what the repo has learned, and the hands-off switch.
struct ApproachDrawer: View {
    let plane: ApproachPlane
    @ObservedObject var store: Store
    @ObservedObject var model: ApproachModel
    let onClose: () -> Void

    @Environment(\.offscreenRender) private var offscreen
    @AppStorage("signalColour") private var signalKey = "amber"
    private var signal: Color { Gotham.signal(signalKey) }

    var body: some View {
        WinScroll {
            VStack(alignment: .leading, spacing: 0) {
                header
                gates
                rounds
                teach
                lessons
                tendToggle
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
        }
        .frame(width: 470)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(hex: "09090C"))
        .overlay(alignment: .leading) { Rectangle().fill(Gotham.edge).frame(width: 1) }
        .shadow(color: .black.opacity(0.6), radius: 40, x: -30)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plane.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Gotham.fg)
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(plane.slug) #\(String(plane.n)) · \(plane.label)")
                    .font(.system(size: 12))
                    .foregroundStyle(Gotham.mute)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Gotham.mute)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Gotham.row))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    /// The four gates: CI, threads, approval and readiness, each with its state and whose move it is.
    private var gates: some View {
        VStack(spacing: 0) {
            ForEach(plane.gates.indices, id: \.self) { i in
                let gate = plane.gates[i]
                HStack(spacing: 10) {
                    GateMark(state: gate.state, colour: signal)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gate.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Gotham.fg)
                        Text(gate.detail)
                            .font(.system(size: 12))
                            .foregroundStyle(Gotham.mute)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Text(gate.who ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(gate.state == .wait ? signal : approachFaint)
                        .lineLimit(1)
                }
                .padding(.vertical, 10)
                .overlay(alignment: .bottom) { Rectangle().fill(Gotham.edge).frame(height: 1) }
            }
        }
        .padding(.top, 20)
    }

    /// Today's tend rounds on this PR, newest first, with the time, tokens and what the round said.
    private var rounds: some View {
        let target = "pr:\(plane.slug)#\(plane.n)"
        let runs = store.snap.tendRounds.filter { $0.target == target }
        let limit = store.snap.config?.tend.roundsPerDay ?? TendConfig().roundsPerDay
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                capLabel("Rounds today")
                Spacer(minLength: 0)
                Text("\(runs.count) of \(limit)")
                    .font(.system(size: 11))
                    .foregroundStyle(approachFaint)
            }
            .padding(.top, 24)
            .padding(.bottom, 10)
            if runs.isEmpty {
                Text("No rounds today")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.mute)
            }
            ForEach(runs, id: \.id) { run in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(HeaderCopy.clock(run.started))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Gotham.fg)
                        Spacer(minLength: 8)
                        Text("\(compactTokens(run.tokens)) tokens")
                            .font(.system(size: 12))
                            .foregroundStyle(Gotham.mute)
                    }
                    Text(roundSummary(run))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Gotham.mute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                .padding(.bottom, 8)
            }
        }
    }

    /// What the round said about this PR: the reason the run recorded, else its error, else nothing.
    private func roundSummary(_ run: RunState) -> String {
        let reason = run.repos.flatMap(\.prs).first { $0.n == plane.n }?.reason
        return reason ?? run.error ?? ""
    }

    /// Teach the repo a rule. The text is kept as a lesson in the repo's playbook, for later rounds.
    private var teach: some View {
        HStack(spacing: 8) {
            if offscreen {
                FieldStandIn(text: model.teach, placeholder: "Teach Glidepath about this repo… e.g. never edit migrations",
                             font: .system(size: 12.5), height: 34, radius: 10)
            } else {
                TextField("Teach Glidepath about this repo… e.g. never edit migrations", text: $model.teach)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.fg)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: "0C0C10")))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Gotham.edge, lineWidth: 1))
                    .onSubmit { model.teachRepo(plane.slug, store: store) }
            }
            SettingButton(title: "Teach") { model.teachRepo(plane.slug, store: store) }
        }
        .padding(.top, 18)
    }

    /// The repo's playbook: its newest six lessons, and the commands it has verified most.
    private var lessons: some View {
        let playbook = store.playbook(plane.slug)
        let recent = playbook.lessons.sorted { $0.date > $1.date }.prefix(6)
        let commands = playbook.commands.sorted { $0.verified > $1.verified }.prefix(3)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                capLabel("Learned in \(plane.slug.split(separator: "/").last.map(String.init) ?? plane.slug)")
                Spacer(minLength: 0)
                Text("\(playbook.lessons.count) lessons")
                    .font(.system(size: 11))
                    .foregroundStyle(approachFaint)
            }
            .padding(.top, 24)
            .padding(.bottom, 8)
            ForEach(Array(commands), id: \.command) { command in
                lessonRow(Text(command.command).font(.system(size: 12, design: .monospaced)).foregroundColor(Gotham.fg),
                          "verified \(command.verified)×")
            }
            ForEach(Array(recent.enumerated()), id: \.offset) { _, lesson in
                lessonRow(Text(lesson.text).font(.system(size: 12.5)).foregroundColor(Gotham.mute),
                          "\(lesson.source) · \(ApproachDrawer.age(lesson.date))")
            }
            if playbook.lessons.isEmpty && playbook.commands.isEmpty {
                Text("Nothing learned yet")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Gotham.mute)
            }
        }
    }

    private func lessonRow(_ text: Text, _ note: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            text.frame(maxWidth: .infinity, alignment: .leading)
            Text(note)
                .font(.system(size: 11))
                .foregroundStyle(approachFaint)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .overlay(alignment: .bottom) { Rectangle().fill(Gotham.edge).frame(height: 1) }
    }

    /// "today", "3 d" or "2 w": how long ago a lesson was learned.
    static func age(_ date: Date, now: Date = Date()) -> String {
        let days = Calendar.current.dateComponents([.day], from: date, to: now).day ?? 0
        if days < 1 { return "today" }
        return days < 7 ? "\(days) d" : "\(days / 7) w"
    }

    /// Glidepath tends this PR unless it is switched off here, or the PR has the hands-off label.
    private var tendToggle: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingSwitch(isOn: !plane.off, label: "Glidepath tends this PR") {
                model.setTending(!plane.off, plane: plane, store: store)
            }
            Text("Glidepath tends this PR · or add the ")
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
            + Text("glidepath:hands-off")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Gotham.mute)
            + Text(" label")
                .font(.system(size: 12))
                .foregroundStyle(Gotham.mute)
        }
        .padding(.top, 18)
    }
}

/// The gate's mark: a dot when it passes, a ring in the signal colour when it waits on someone, a ring that is part
/// open when work is under way, and a faint ring when it does not apply.
private struct GateMark: View {
    let state: GateState
    let colour: Color

    var body: some View {
        ZStack {
            switch state {
            case .ok:
                Circle().fill(Gotham.fg).frame(width: 14, height: 14)
            case .wait:
                Circle().strokeBorder(colour, lineWidth: 1.5).frame(width: 14, height: 14)
                    .shadow(color: colour.opacity(0.4), radius: 3)
            case .work:
                Circle().trim(from: 0.25, to: 1).stroke(Gotham.fg, lineWidth: 1.5).frame(width: 14, height: 14)
                    .rotationEffect(.degrees(-90))
            case .none:
                Circle().strokeBorder(approachFaint, lineWidth: 1.5).frame(width: 14, height: 14)
            }
        }
    }
}

/// The Approach section's state: the open plane, the teach text, and the tower lines opened.
@MainActor
final class ApproachModel: ObservableObject {
    init(opened: String? = nil) { self.opened = opened }

    /// The plane whose drawer is open, by `ApproachPlane.id`.
    @Published var opened: String?
    /// The text in the drawer's teach field.
    @Published var teach = ""
    /// Tower lines whose detail is open, by key.
    @Published var expanded: Set<String> = []

    func toggle(_ key: String) {
        if expanded.contains(key) { expanded.remove(key) } else { expanded.insert(key) }
    }

    /// Turns the Autopilot switch in config.toml.
    func setAutopilot(_ on: Bool, store: Store) {
        save(store) { ConfigEditor.setAutopilot($0, on) }
    }

    /// Writes one lesson the user taught to the repo's playbook, then clears the field.
    func teachRepo(_ slug: String, store: Store) {
        let text = teach.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        teach = ""
        let paths = store.paths
        Task {
            await Task.detached {
                let book = Playbook.load(slug, paths: paths).teach(text, source: "you taught", date: Date())
                try? book.save(slug, paths: paths)
            }.value
            store.reload()
        }
    }

    /// Switches tending on or off for one PR: the PR's state file keeps the `off` flag.
    func setTending(_ on: Bool, plane: ApproachPlane, store: Store) {
        let paths = store.paths
        let slug = plane.slug, n = plane.n
        Task {
            await Task.detached {
                let tend = TendStore(paths: paths)
                var state = tend.load(slug, n) ?? TendPR(slug: slug, n: n)
                state.off = !on
                try? tend.save(state)
            }.value
            store.reload()
        }
    }

    /// Applies one config edit to config.toml as it is on disk, then reloads the store.
    private func save(_ store: Store, _ change: @escaping @Sendable (Config) throws -> Config) {
        let paths = store.paths
        Task {
            try? await ConfigWriter.shared.apply(paths: paths, change: change) { try ConfigEditor.save($0, paths: paths) }
            store.reload()
        }
    }
}
