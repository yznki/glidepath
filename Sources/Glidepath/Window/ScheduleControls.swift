import SwiftUI

/// The dial's state: the window (start, span, interval), the days, and the custom times when no window describes them.
/// Every edit the user makes goes through the methods here and calls `onChange`, which the owner uses to save. Shared by
/// the Schedule section and the onboarding schedule step.
@MainActor
final class DialEditor: ObservableObject {
    @Published private(set) var window = DialWindow(start: 540, span: 540, every: 30)
    @Published private(set) var days: Set<Weekday> = DialPreset.weekdays
    /// Times that no window describes. They show as dots with no arc until the user drags.
    @Published private(set) var custom: [ScheduleTime]?
    /// Counts refused changes; each step is one shake.
    @Published private(set) var shake: CGFloat = 0
    /// Called after each change the user makes. Not called by `load`.
    var onChange: () -> Void = {}

    /// Drag bookkeeping for the dial view. Not published: the window changes are.
    private(set) var dragActive = false
    private(set) var dragHit: DialHit = .none
    private var dragY0: CGFloat = 0
    private var dragEvery0 = 30

    /// The sweep times the dial stands for.
    var times: [ScheduleTime] { custom ?? window.times }
    var scheduleDays: ScheduleDays { DialDays.schedule(days) }

    /// Takes a schedule as the dial shows it. Times no window describes become custom times.
    func load(times: [ScheduleTime], days: ScheduleDays) {
        self.days = DialDays.set(days)
        if let window = DialWindow.from(times: times) {
            custom = nil
            self.window = window
        } else {
            custom = times
        }
    }

    /// True when the dial already stands on `preset`, so its button shows pressed.
    func matches(_ preset: DialPreset) -> Bool {
        custom == nil && window.times == preset.window.times && days == preset.days
    }

    /// The window standing in for custom times, when the user first drags.
    private static func dialWindow(fromCustom times: [ScheduleTime]) -> DialWindow {
        let minutes = times.map(\.minutes).sorted()
        let first = minutes.first ?? 540
        let last = minutes.last ?? first
        return DialWindow(start: first, span: last - first, every: 60)
    }

    /// Applies one change to the window. Custom times become a window first. Nothing is reported when nothing changed.
    private func edit(_ change: (DialWindow) -> DialWindow) {
        let base = custom.map(Self.dialWindow(fromCustom:)) ?? window
        let next = change(base)
        guard custom != nil || next != window else { return }
        custom = nil
        window = next
        onChange()
    }

    func moveStart(to minute: Int) {
        edit { $0.movedStart(to: minute) }
    }

    func moveEnd(to minute: Int) {
        edit { $0.movedEnd(to: minute) }
    }

    /// Changes the interval by `step` quarter-hour-based steps: positive is less often. Clamped to 15...240.
    func stepEvery(_ step: Int) {
        edit { DialWindow(start: $0.start, span: $0.span, every: $0.every + 15 * step) }
    }

    /// A centre drag: the interval follows the pointer, 15 minutes per 14 points, relative to where the drag began.
    func dragCentre(y: CGFloat) {
        let every = dragEvery0 + Int(((dragY0 - y) / 14).rounded()) * 15
        edit { DialWindow(start: $0.start, span: $0.span, every: every) }
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

    func apply(_ preset: DialPreset, animated: Bool) {
        guard !matches(preset) else { return }
        withAnimation(animated ? Animation.easeOut(duration: 0.65) : nil) {
            custom = nil
            window = preset.window
            days = preset.days
        }
        onChange()
    }

    /// Turns a day on or off. The last day on cannot go off: it shakes instead.
    func toggleDay(_ day: Weekday, animated: Bool) {
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
        onChange()
    }
}

/// Where a drag on the dial began.
/// Where a drag on the dial began.
enum DialHit: Equatable { case none, start, end, centre }


/// The dial with its −/+ buttons, and the save error under it when there is one.
struct ScheduleDialView: View {
    @ObservedObject var dial: DialEditor
    let reduced: Bool
    let signal: Color
    var error: String?

    var body: some View {
        VStack(spacing: 10) {
            DialView(start: Double(dial.window.start), span: Double(dial.window.span),
                     every: Double(dial.window.every), dial: dial, custom: dial.custom, reduced: reduced, signal: signal)
            HStack(spacing: 8) {
                roundButton("−") { dial.stepEvery(1) }
                Spacer(minLength: 4)
                Text(dial.custom == nil ? "Drag the ends · scroll the centre" : "Custom · drag to set")
                    .cap()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                roundButton("+") { dial.stepEvery(-1) }
            }
            .frame(width: DialView.side)
            if let error {
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
}

/// The four presets as a two-column grid. The one the dial already stands on shows pressed.
struct PresetGrid: View {
    @ObservedObject var dial: DialEditor
    let reduced: Bool

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(DialPreset.all, id: \.key) { preset in presetButton(preset) }
        }
    }

    private func presetButton(_ preset: DialPreset) -> some View {
        let pressed = dial.matches(preset)
        return Button {
            dial.apply(preset, animated: !reduced)
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
}

/// The seven day pills. The last day on cannot go off: it shakes instead.
struct DayPills: View {
    @ObservedObject var dial: DialEditor
    let reduced: Bool
    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.allCases, id: \.self) { day in
                let on = dial.days.contains(day)
                Button {
                    dial.toggleDay(day, animated: !reduced)
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
        .modifier(ShakeEffect(animatableData: dial.shake))
    }
}

/// Press feedback for the dial's buttons. The scale is skipped under reduced motion.
struct PressStyle: ButtonStyle {
    var reduced: Bool
    var scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(reduced ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// A horizontal shake for a refused change. `animatableData` counts shakes; whole numbers are at rest.
struct ShakeEffect: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 7 * sin(animatableData * .pi * 4), y: 0))
    }
}

/// Keys: the knobs and the centre are focusable. Focus enlarges the knob.
enum DialFocus: Hashable { case start, end, centre }

/// A scroll-wheel probe: a local monitor that takes scroll events over the dial's centre and passes their steps on.
/// It takes no clicks (`hitTest` is nil), so the drag gesture keeps them.
struct ScrollProbe: NSViewRepresentable {
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
struct DialView: View, Animatable {
    static let side: CGFloat = 300

    var start: Double
    var span: Double
    var every: Double
    @ObservedObject var dial: DialEditor
    let custom: [ScheduleTime]?
    let reduced: Bool
    let signal: Color
    @FocusState private var focus: DialFocus?

    init(start: Double, span: Double, every: Double, dial: DialEditor,
         custom: [ScheduleTime]?, reduced: Bool, signal: Color) {
        self.start = start
        self.span = span
        self.every = every
        _dial = ObservedObject(wrappedValue: dial)
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
        SnapshotTimeline(schedule: .periodic(from: .now, by: reduced ? 30 : 1.0 / 30)) { date in
            ZStack {
                Canvas { canvas, _ in
                    draw(&canvas, now: date)
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
                        dial.stepEvery(step)
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
        guard let next = DialUpcoming.next(1, after: now, times: dial.times, days: dial.scheduleDays).first,
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
        case .start: dial.moveStart(to: dial.window.start + 15 * step)
        case .end: dial.moveEnd(to: dial.window.end + 15 * step)
        case .centre: dial.stepEvery(step)
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
                if !dial.dragActive {
                    dial.beginDrag(hit(at: value.startLocation), y: value.startLocation.y)
                }
                let dx = Double(value.location.x - centre.x), dy = Double(value.location.y - centre.y)
                switch dial.dragHit {
                case .start: dial.moveStart(to: DialWindow.minute(dx: dx, dy: dy))
                case .end: dial.moveEnd(to: DialWindow.minute(dx: dx, dy: dy))
                case .centre: dial.dragCentre(y: value.location.y)
                case .none: break
                }
            }
            .onEnded { _ in dial.endDrag() }
    }
}
