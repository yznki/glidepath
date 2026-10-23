import SwiftUI

/// The Schedule section (1.3 prototype `.sched`): a 24 h dial for the sweep window and interval, presets, day pills,
/// the numbers under them, the next eight sweeps, and the pause control. Changes save 0.4 s after the last one through
/// `ScheduleEditor`, which reinstalls the launchd job.
struct ScheduleView: View {
    @ObservedObject var store: Store
    @StateObject private var model = ScheduleModel()
    @AppStorage("signalColour") private var signalKey = "amber"
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reduced: Bool { Motion.reduced(reduceMotion) }
    private var signal: Color { Gotham.signal(signalKey) }
    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                HStack(alignment: .top, spacing: 34) {
                    dialColumn
                    sideColumn
                }
                .padding(.top, 24)
                upcomingSection
                    .padding(.top, 32)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            ScheduleModel.live = model
            model.sync(store.snap.config)
        }
        .onChange(of: store.snap.schedule) { _, _ in model.sync(store.snap.config) }
        .onChange(of: store.snap.config?.days) { _, _ in model.sync(store.snap.config) }
        .onDisappear { model.flush(store) }
    }

    // MARK: Header

    private var header: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let next = DialUpcoming.next(1, after: context.date, times: model.times, days: model.scheduleDays).first
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Schedule")
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(Gotham.fg)
                        SavedNote(saved: model.saved)
                    }
                    Text(status(now: context.date, next: next))
                        .monospacedDigit()
                        .cap()
                }
                Spacer(minLength: 16)
                pauseControl(now: context.date)
            }
        }
    }

    private func status(now: Date, next: Date?) -> String {
        if store.snap.paused { return "Paused" }
        guard let next else { return "No sweeps scheduled" }
        let minutes = Int(next.timeIntervalSince(now) / 60)
        return "Next \(DialFormat.clock(next)) · in \(DialFormat.interval(minutes: minutes))"
    }

    /// Running, Pause 1 h, Until tomorrow. The segment that matches the marker file is filled.
    private func pauseControl(now: Date) -> some View {
        let paused = store.snap.paused
        let selected: SchedulePause?
        if !paused {
            selected = .running
        } else if let until = Pause.until(store.paths) {
            selected = until.timeIntervalSince(now) <= 3700 ? .hour : .tomorrow
        } else {
            selected = nil
        }
        return HStack(spacing: 2) {
            ForEach(SchedulePause.allCases, id: \.self) { choice in
                let on = selected == choice
                Button {
                    model.setPause(choice, store: store, now: Date())
                } label: {
                    Text(choice.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(on ? Color(hex: "060607") : Gotham.mute)
                        .padding(.horizontal, 12)
                        .frame(height: 26)
                        .background(Capsule().fill(on ? Gotham.fg : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Gotham.row))
        .overlay(Capsule().strokeBorder(Gotham.edge, lineWidth: 1))
    }

    // MARK: Dial column

    private var dialColumn: some View {
        VStack(spacing: 10) {
            DialView(start: Double(model.window.start), span: Double(model.window.span),
                     every: Double(model.window.every), model: model, store: store,
                     custom: model.custom, reduced: reduced, signal: signal)
            HStack(spacing: 8) {
                roundButton("−") { model.stepEvery(1, store: store) }
                Spacer(minLength: 4)
                Text(model.custom == nil ? "Drag the ends · scroll the centre" : "Custom times · drag to replace")
                    .cap()
                    .multilineTextAlignment(.center)
                Spacer(minLength: 4)
                roundButton("+") { model.stepEvery(-1, store: store) }
            }
            .frame(width: DialView.side)
            if let error = model.error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(signal)
                    .frame(width: DialView.side, alignment: .leading)
            }
        }
        .frame(width: DialView.side)
    }

    private func roundButton(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 14))
                .foregroundStyle(Gotham.fg)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Gotham.row))
                .overlay(Circle().strokeBorder(Gotham.edge, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle(reduced: reduced, scale: 0.9))
    }

    // MARK: Side column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Presets").cap()
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(DialPreset.all, id: \.key) { preset in presetButton(preset) }
            }
            .padding(.top, 12)
            Text("Days").cap().padding(.top, 26)
            dayPills.padding(.top, 12)
            stats.padding(.top, 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func presetButton(_ preset: DialPreset) -> some View {
        let pressed = model.matches(preset)
        return Button {
            model.apply(preset, store: store, animated: !reduced)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(preset.name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Gotham.fg)
                Text(preset.detail).cap()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14).fill(Gotham.row))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(pressed ? Gotham.fg : Gotham.edge, lineWidth: pressed ? 1.5 : 1))
            .shadow(color: pressed ? .white.opacity(0.3) : .clear, radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(PressStyle(reduced: reduced, scale: 0.98))
    }

    private var dayPills: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = model.days.contains(day)
                Button {
                    model.toggleDay(day, store: store, animated: !reduced)
                } label: {
                    Text(Self.letters[day.rawValue])
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(on ? Color(hex: "060607") : Gotham.mute)
                        .frame(width: 35, height: 35)
                        .background(Circle().fill(on ? Gotham.fg : Gotham.row))
                        .overlay(Circle().strokeBorder(Gotham.edge, lineWidth: 1))
                        .shadow(color: on ? .white.opacity(0.35) : .clear, radius: 9)
                        .springy(value: on)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle(reduced: reduced, scale: 0.9))
                .accessibilityLabel(day.name.capitalized)
            }
        }
        .modifier(ShakeEffect(animatableData: model.shake))
    }

    /// Sweeps a day, a week, and the month's tokens estimate. Over the budget (when one is set) the last one turns
    /// into the signal colour.
    private var stats: some View {
        let perDay = model.times.count
        let perWeek = perDay * model.days.count
        let tokens = DialStats.tokensPerMonth(perWeek: perWeek)
        let over = DialStats.overBudget(tokens: tokens, budget: store.snap.config?.monthlyTokens ?? 0)
        return HStack(alignment: .top, spacing: 26) {
            stat("\(perDay)", "Sweeps a day", warn: false)
            stat("\(perWeek)", "A week", warn: false)
            stat("~" + DialFormat.compact(tokens), over ? "Over budget" : "Tokens a month", warn: over)
        }
    }

    private func stat(_ value: String, _ label: String, warn: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(Gotham.numeral(26))
                .monospacedDigit()
                .foregroundStyle(warn ? signal : Gotham.fg)
            Text(label)
                .cap()
                .foregroundStyle(warn ? signal : Gotham.mute)
        }
    }

    // MARK: Upcoming

    private var upcomingSection: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let dates = DialUpcoming.next(8, after: context.date, times: model.times, days: model.scheduleDays)
            VStack(alignment: .leading, spacing: 14) {
                Text("Upcoming").cap()
                if dates.isEmpty {
                    Text("No sweeps scheduled. Pick at least one day.").cap()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            ForEach(Array(dates.enumerated()), id: \.offset) { index, date in
                                upcomingTick(date, first: index == 0, now: context.date)
                            }
                        }
                        .background(alignment: .topLeading) {
                            Rectangle().fill(Gotham.edge).frame(height: 1).padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    private func upcomingTick(_ date: Date, first: Bool, now: Date) -> some View {
        VStack(spacing: 7) {
            Circle()
                .fill(first ? Gotham.fg : Gotham.void)
                .overlay(Circle().strokeBorder(first ? Color.clear : Gotham.mute, lineWidth: 1.5))
                .frame(width: 9, height: 9)
                .shadow(color: first ? .white.opacity(0.8) : .clear, radius: 6)
            Text(DialFormat.clock(date))
                .font(.system(size: 17, weight: .light))
                .monospacedDigit()
                .foregroundStyle(Gotham.fg)
            Text(Calendar.current.isDate(date, inSameDayAs: now) ? "Today" : date.formatted(.dateTime.weekday(.abbreviated)))
                .cap()
        }
        .frame(width: 72)
    }
}

// MARK: - Pieces

/// The pause segments.
enum SchedulePause: CaseIterable {
    case running, hour, tomorrow

    var title: String {
        switch self {
        case .running: return "Running"
        case .hour: return "Pause 1 h"
        case .tomorrow: return "Until tomorrow"
        }
    }
}

/// Where a drag on the dial began.
enum DialHit: Equatable { case none, start, end, centre }

/// The "Saved" stamp. Observes `SavedFlash` directly, since the model does not forward its changes.
private struct SavedNote: View {
    @ObservedObject var saved: SavedFlash

    var body: some View {
        Text("Saved")
            .cap()
            .opacity(saved.shown ? 1 : 0)
    }
}

/// Press feedback for the dial's buttons. The scale is skipped under reduced motion.
private struct PressStyle: ButtonStyle {
    var reduced: Bool
    var scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(reduced ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A horizontal shake for a refused change. `animatableData` counts shakes; whole numbers are at rest.
private struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Keys: the knobs and the centre are focusable. Focus enlarges the knob.
private enum DialFocus: Hashable { case start, end, centre }

/// A scroll-wheel probe: a local monitor that takes scroll events over the dial's centre and passes their steps on.
/// It takes no clicks (`hitTest` is nil), so the drag gesture keeps them.
private struct ScrollProbe: NSViewRepresentable {
    let centre: CGPoint
    let radius: CGFloat
    let onStep: (Int) -> Void

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        view.centre = centre
        view.radius = radius
        view.onStep = onStep
    }

    final class ProbeView: NSView {
        var centre = CGPoint.zero
        var radius: CGFloat = 0
        var onStep: ((Int) -> Void)?
        private var monitor: Any?
        private var accumulated: CGFloat = 0

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            removeMonitor()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard hypot(p.x - self.centre.x, p.y - self.centre.y) <= self.radius else { return event }
                self.accumulated += event.scrollingDeltaY
                if abs(self.accumulated) >= 8 {
                    // Scrolling up (negative delta) lengthens the interval, as on the prototype.
                    self.onStep?(self.accumulated < 0 ? 1 : -1)
                    self.accumulated = 0
                }
                return nil
            }
        }

        private func removeMonitor() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { removeMonitor() }
    }
}

/// The dial. Animatable over the window's start, span and interval, so a preset tweens through `withAnimation`.
/// Drawn with Canvas in a 348-unit space scaled to `side`, midnight at the top.
private struct DialView: View, Animatable {
    static let side: CGFloat = 300

    var start: Double
    var span: Double
    var every: Double
    let model: ScheduleModel
    let store: Store
    let custom: [ScheduleTime]?
    let reduced: Bool
    let signal: Color
    @FocusState private var focus: DialFocus?

    init(start: Double, span: Double, every: Double, model: ScheduleModel, store: Store,
         custom: [ScheduleTime]?, reduced: Bool, signal: Color) {
        self.start = start
        self.span = span
        self.every = every
        self.model = model
        self.store = store
        self.custom = custom
        self.reduced = reduced
        self.signal = signal
    }

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(start, AnimatablePair(span, every)) }
        set {
            start = newValue.first
            span = newValue.second.first
            every = newValue.second.second
        }
    }

    @Environment(\.offscreenRender) private var offscreen
    private var k: CGFloat { Self.side / 348 }
    private var centre: CGPoint { CGPoint(x: Self.side / 2, y: Self.side / 2) }
    private var full: Bool { span >= 1440 }
    private var endMinute: Double { start + span }

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduced ? 30 : 1.0 / 30)) { context in
            ZStack {
                Canvas { canvas, _ in
                    draw(&canvas, now: context.date)
                }
                if custom == nil {
                    focusTarget(.start, at: point(start, 128), size: 28 * k)
                    focusTarget(.end, at: point(endMinute, 128), size: 28 * k)
                }
                focusTarget(.centre, at: centre, size: 128 * k)
            }
            .frame(width: Self.side, height: Self.side)
            .contentShape(Rectangle())
            .gesture(drag)
            .background {
                // Snapshots draw no scroll wheel; ImageRenderer draws the representable as a prohibition sign.
                if !offscreen {
                    ScrollProbe(centre: centre, radius: 64 * k) { step in
                        model.stepEvery(step, store: store)
                    }
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
    }

    // MARK: Geometry

    /// The point at `minute` on the ring of radius `r` (348-unit space).
    private func point(_ minute: Double, _ r: CGFloat) -> CGPoint {
        let a = minute / 1440 * 2 * Double.pi - Double.pi / 2
        return CGPoint(x: centre.x + r * k * CGFloat(cos(a)), y: centre.y + r * k * CGFloat(sin(a)))
    }

    private func circle(_ p: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
    }

    /// The arc from start to end, sampled every 5 minutes so it follows the ring exactly.
    private func arcPath(_ r: CGFloat) -> Path {
        var path = Path()
        let steps = max(2, Int(span / 5))
        for i in 0...steps {
            let p = point(start + span * Double(i) / Double(steps), r)
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }

    /// The minute of the day of the next sweep, when it is today.
    private func nextMinuteToday(_ now: Date) -> Int? {
        guard let next = DialUpcoming.next(1, after: now, times: model.times, days: model.scheduleDays).first,
              Calendar.current.isDate(next, inSameDayAs: now) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: next)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    // MARK: Drawing

    private func draw(_ c: inout GraphicsContext, now: Date) {
        let w = 18 * k
        // Base ring.
        c.stroke(circle(centre, 128 * k), with: .color(Gotham.row), lineWidth: w)

        if custom == nil {
            // Glowing arc, from start to end (the whole ring for a whole day).
            let arc = full ? circle(centre, 128 * k) : arcPath(128)
            var glow = c
            glow.addFilter(.blur(radius: 6 * k))
            glow.stroke(arc, with: .color(Gotham.fg.opacity(0.35)), style: StrokeStyle(lineWidth: w, lineCap: .round))
            c.stroke(arc, with: .color(Gotham.fg), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }

        // Ticks every hour, labels at 00, 06, 12, 18.
        for h in 0..<24 {
            let major = h % 6 == 0
            var tick = Path()
            tick.move(to: point(Double(h * 60), 146))
            tick.addLine(to: point(Double(h * 60), major ? 153 : 150))
            c.stroke(tick, with: .color(Gotham.mute.opacity(major ? 1 : 0.5)), lineWidth: (major ? 1.5 : 1) * k)
        }
        for h in [0, 6, 12, 18] {
            c.draw(Text(String(format: "%02d", h))
                .font(.system(size: 9 * k, weight: .semibold))
                .tracking(1.1 * k)
                .foregroundStyle(Gotham.mute),
                at: point(Double(h * 60), 166), anchor: .center)
        }

        // Sweep dots. The next sweep, when it is today, is larger and breathes (not under reduced motion).
        let nextMinute = nextMinuteToday(now)
        let phase: CGFloat = reduced ? 0.5 : CGFloat((1 + sin(now.timeIntervalSinceReferenceDate * .pi)) / 2)
        let dots: [Double]
        if let custom {
            dots = custom.map { Double($0.minutes) }
        } else {
            dots = Array(stride(from: 0.0, through: span - (full ? 1 : 0), by: every)).map { start + $0 }
        }
        for minute in dots {
            let p = point(minute, 104)
            if let nextMinute, Int(minute.rounded()) % 1440 == nextMinute {
                let r = 4.5 * k * (reduced ? 1 : 0.85 + 0.25 * phase)
                var glow = c
                glow.addFilter(.blur(radius: 4 * k))
                glow.fill(circle(p, r * 1.6), with: .color(.white.opacity(0.8)))
                c.fill(circle(p, r), with: .color(.white))
            } else {
                c.fill(circle(p, 2.2 * k), with: .color(Gotham.fg.opacity(0.55)))
            }
        }

        // Now hand, in the signal colour.
        let parts = Calendar.current.dateComponents([.hour, .minute, .second], from: now)
        let nowMinute = Double((parts.hour ?? 0) * 60 + (parts.minute ?? 0)) + Double(parts.second ?? 0) / 60
        var hand = Path()
        hand.move(to: point(nowMinute, 74))
        hand.addLine(to: point(nowMinute, 138))
        c.stroke(hand, with: .color(signal), style: StrokeStyle(lineWidth: 1.5 * k, lineCap: .round))
        c.fill(circle(point(nowMinute, 138), 3 * k), with: .color(signal))

        // Knobs and their times.
        if custom == nil {
            for (minute, focused, isEnd) in [(start, focus == .start, false), (endMinute, focus == .end, true)] {
                if isEnd && full { continue }
                let p = point(minute, 128)
                let r = (focused ? 11.5 : 9.5) * k
                c.fill(circle(p, r), with: .color(Color(hex: "0B0B0E")))
                c.stroke(circle(p, r), with: .color(Gotham.fg), lineWidth: 2.5 * k)
                c.draw(Text(DialFormat.clock(minute: Int(minute.rounded())))
                    .font(.system(size: 10 * k, weight: .semibold))
                    .foregroundStyle(Gotham.fg),
                    at: CGPoint(x: p.x, y: p.y - 14 * k), anchor: .bottom)
            }
        }

        // Centre: the interval.
        c.fill(circle(centre, 64 * k), with: .color(Gotham.row))
        c.stroke(circle(centre, 64 * k), with: .color(Gotham.edge), lineWidth: k)
        if focus == .centre {
            c.stroke(circle(centre, 66 * k), with: .color(Gotham.fg), lineWidth: 1.5 * k)
        }
        let every = Int(self.every.rounded())
        let big: String
        let unit: String
        if every < 60 {
            big = "\(every)"
            unit = "MINUTES"
        } else if every == 60 {
            big = "1"
            unit = "HOUR"
        } else {
            big = every % 60 == 0 ? "\(every / 60)" : String(format: "%.2f", Double(every) / 60).replacingOccurrences(of: "0$", with: "", options: .regularExpression)
            unit = "HOURS"
        }
        c.draw(Text(big)
            .font(Gotham.numeral(46 * k))
            .monospacedDigit()
            .foregroundStyle(Gotham.fg),
            at: CGPoint(x: centre.x, y: centre.y - 4 * k), anchor: .center)
        c.draw(Text(unit)
            .font(.system(size: 8.5 * k, weight: .semibold))
            .tracking(2 * k)
            .foregroundStyle(Gotham.mute),
            at: CGPoint(x: centre.x, y: centre.y + 30 * k), anchor: .center)
    }

    // MARK: Interaction

    /// Keyboard focus targets. Invisible; they take focus and keys, not the mouse.
    private func focusTarget(_ target: DialFocus, at p: CGPoint, size: CGFloat) -> some View {
        Circle()
            .fill(Color.clear)
            .frame(width: size, height: size)
            .position(p)
            .focusable()
            .focusEffectDisabled()
            .focused($focus, equals: target)
            .allowsHitTesting(false)
            .onKeyPress(phases: .down) { press in keyDown(target, press) }
    }

    private func keyDown(_ target: DialFocus, _ press: KeyPress) -> KeyPress.Result {
        let step: Int
        switch press.key {
        case .upArrow, .rightArrow: step = 1
        case .downArrow, .leftArrow: step = -1
        default: return .ignored
        }
        switch target {
        case .start: model.moveStart(to: model.window.start + 15 * step, store: store)
        case .end: model.moveEnd(to: model.window.end + 15 * step, store: store)
        case .centre: model.stepEvery(step, store: store)
        }
        return .handled
    }

    /// Which knob, if any, a press at `p` grabs. Inside the centre is the interval. With custom times, the ring is
    /// the handle: any press on it replaces them.
    private func hit(at p: CGPoint) -> DialHit {
        let dx = p.x - centre.x, dy = p.y - centre.y
        if hypot(dx, dy) < 64 * k + 6 { return .centre }
        if custom != nil {
            return abs(hypot(dx, dy) - 128 * k) < 24 ? .start : .none
        }
        let ps = point(start, 128), pe = point(endMinute, 128)
        let ds = hypot(p.x - ps.x, p.y - ps.y), de = hypot(p.x - pe.x, p.y - pe.y)
        if min(ds, de) > 20 { return .none }
        return de <= ds ? .end : .start   // on a whole day both knobs meet: the end one takes the press
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !model.dragActive {
                    model.beginDrag(hit(at: value.startLocation), y: value.startLocation.y)
                }
                let dx = Double(value.location.x - centre.x), dy = Double(value.location.y - centre.y)
                switch model.dragHit {
                case .start: model.moveStart(to: DialWindow.minute(dx: dx, dy: dy), store: store)
                case .end: model.moveEnd(to: DialWindow.minute(dx: dx, dy: dy), store: store)
                case .centre: model.dragCentre(y: value.location.y, store: store)
                case .none: break
                }
            }
            .onEnded { _ in model.endDrag() }
    }
}

// MARK: - Model

/// The Schedule section's state: the dial's window and days, the custom times when no window describes them, the
/// pause and drag bookkeeping, and the debounced save. Every change goes through `edit` or `toggleDay`, which mark the
/// model dirty; `save` writes the times and days through `ScheduleEditor` and reinstalls the job.
@MainActor
final class ScheduleModel: ObservableObject {
    @Published private(set) var window = DialWindow(start: 540, span: 540, every: 30)
    @Published private(set) var days: Set<Weekday> = DialPreset.weekdays
    /// Saved times that no window describes. They show as dots with no arc until the user drags.
    @Published private(set) var custom: [ScheduleTime]?
    /// The last save's error, shown under the dial.
    @Published private(set) var error: String?
    /// Counts refused changes; each step is one shake.
    @Published private(set) var shake: CGFloat = 0
    let saved = SavedFlash()

    /// The model whose window is open, so a window close can flush its pending save.
    static weak var live: ScheduleModel?
    /// Held while a save is pending, so the model outlives its window and quit can still wait for the write.
    private static var pendingSave: ScheduleModel?

    /// Set on every change, cleared when a save starts.
    private var dirty = false
    private var saveInFlight = false
    private var saveTask: Task<Void, Never>?
    /// What config.toml holds as far as this model knows, so a reload of our own save does not reset the dial.
    private var synced: (times: [ScheduleTime], days: ScheduleDays)?

    /// Drag bookkeeping for the dial view. Not published: the window changes are.
    private(set) var dragActive = false
    private(set) var dragHit: DialHit = .none
    private var dragY0: CGFloat = 0
    private var dragEvery0 = 30

    /// The sweep times the dial stands for.
    var times: [ScheduleTime] { custom ?? window.times }
    var scheduleDays: ScheduleDays { DialDays.schedule(days) }

    /// Flushes the live model's pending save, if any. Called when the window closes and the app quits.
    static func flushLive(_ store: Store) {
        live?.flush(store)
    }

    /// True while a change waits to be saved or a save is running.
    var hasPendingSave: Bool { dirty || saveInFlight }

    /// Saves the pending change now: when the section goes away, or the window closes.
    func flush(_ store: Store) {
        saveTask?.cancel()
        save(store)
    }

    /// Saves the pending change and waits for it to land, for quitting. Gives up after `timeout`.
    func flushAndWait(_ store: Store, timeout: TimeInterval) async {
        flush(store)
        let deadline = Date().addingTimeInterval(timeout)
        while hasPendingSave && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: Loading

    /// Takes the config's schedule when it differs from what this model last saved or loaded.
    func sync(_ config: Config?) {
        guard let config, !dirty, !saveInFlight else { return }
        if let synced, synced.times == config.schedule, synced.days == config.days { return }
        synced = (config.schedule, config.days)
        days = DialDays.set(config.days)
        if let window = DialWindow.from(times: config.schedule) {
            custom = nil
            self.window = window
        } else {
            custom = config.schedule
        }
    }

    /// The window standing in for custom times, when the user first drags.
    private static func dialWindow(fromCustom times: [ScheduleTime]) -> DialWindow {
        let minutes = times.map(\.minutes).sorted()
        let first = minutes.first ?? 540
        let last = minutes.last ?? first
        return DialWindow(start: first, span: last - first, every: 60)
    }

    /// True when the dial already stands on `preset`, so its button shows pressed.
    func matches(_ preset: DialPreset) -> Bool {
        custom == nil && window.times == preset.window.times && days == preset.days
    }

    // MARK: Edits

    /// Applies one change to the window. Custom times become a window first. Nothing is marked when nothing changed.
    private func edit(_ store: Store, _ change: (DialWindow) -> DialWindow) {
        let base = custom.map(Self.dialWindow(fromCustom:)) ?? window
        let next = change(base)
        guard custom != nil || next != window else { return }
        custom = nil
        window = next
        changed(store)
    }

    func moveStart(to minute: Int, store: Store) {
        edit(store) { $0.movedStart(to: minute) }
    }

    func moveEnd(to minute: Int, store: Store) {
        edit(store) { $0.movedEnd(to: minute) }
    }

    /// Changes the interval by `step` quarter-hour-based steps: positive is less often. Clamped to 15...240.
    func stepEvery(_ step: Int, store: Store) {
        edit(store) { DialWindow(start: $0.start, span: $0.span, every: $0.every + 15 * step) }
    }

    /// A centre drag: the interval follows the pointer, 15 minutes per 14 points, relative to where the drag began.
    func dragCentre(y: CGFloat, store: Store) {
        let every = dragEvery0 + Int(((dragY0 - y) / 14).rounded()) * 15
        edit(store) { DialWindow(start: $0.start, span: $0.span, every: every) }
    }

    func beginDrag(_ hit: DialHit, y: CGFloat) {
        dragActive = true
        dragHit = hit
        dragY0 = y
        dragEvery0 = window.every
    }

    func endDrag() {
        dragActive = false
        dragHit = .none
    }

    func apply(_ preset: DialPreset, store: Store, animated: Bool) {
        guard !matches(preset) else { return }
        withAnimation(animated ? Animation.easeOut(duration: 0.65) : nil) {
            custom = nil
            window = preset.window
            days = preset.days
        }
        changed(store)
    }

    /// Turns a day on or off. The last day on cannot go off: it shakes instead.
    func toggleDay(_ day: Weekday, store: Store, animated: Bool) {
        var next = days
        if next.contains(day) {
            guard next.count > 1 else {
                if animated { withAnimation(.linear(duration: 0.4)) { shake += 1 } }
                return
            }
            next.remove(day)
        } else {
            next.insert(day)
        }
        days = next
        changed(store)
    }

    // MARK: Pause

    /// Running resumes; the two pauses write the marker file, so the launchd job sees them.
    func setPause(_ choice: SchedulePause, store: Store, now: Date) {
        do {
            switch choice {
            case .running:
                try Pause.set(false, store.paths)
            case .hour:
                try Pause.set(true, store.paths, until: now.addingTimeInterval(3600))
            case .tomorrow:
                let until = DialPause.tomorrow(now: now, times: times, days: scheduleDays)
                try Pause.set(true, store.paths, until: until ?? now.addingTimeInterval(86400))
            }
            error = nil
        } catch {
            self.error = "Pause: \(error.localizedDescription)"
        }
        store.reload()
    }

    // MARK: Saving

    /// Marks a change and saves 0.4 s after the last one.
    private func changed(_ store: Store) {
        dirty = true
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self.save(store)
        }
    }

    /// Writes the times and days in one config edit and reinstalls the job, as the old Schedule section did. One save
    /// runs at a time; a change made meanwhile saves once it lands.
    private func save(_ store: Store) {
        guard dirty, !saveInFlight else { return }
        dirty = false
        saveInFlight = true
        Self.pendingSave = self
        let times = self.times
        let days = self.scheduleDays
        let paths = store.paths
        Task {
            do {
                _ = try await ConfigWriter.shared.apply(paths: paths, change: { config in
                    try ScheduleEditor.setDays(try ScheduleEditor.setSchedule(config, times), days)
                }) { try ScheduleEditor.save($0, paths: paths) }
                error = nil
                synced = (times, days)
                saved.flash()
            } catch let failure as ConfigError {
                error = failure.message
            } catch {
                self.error = "Could not save: \(error.localizedDescription)"
            }
            saveInFlight = false
            Self.pendingSave = nil
            store.reload()
            if dirty { save(store) }
        }
    }
}
