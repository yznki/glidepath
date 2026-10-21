import SwiftUI

extension ScheduleDays {
    /// The segment this setting shows under Days.
    fileprivate var choice: ScheduleView.DayChoice {
        switch self {
        case .weekdays: return .weekdays
        case .all: return .everyDay
        case .custom: return .custom
        }
    }
}

/// The Schedule section (v1.2 mockup 8-schedule): a 24 h day strip with the sweep times as pins, the times as chips,
/// the days, the per-sweep limits and this week's counts. Each change saves at once through `ScheduleEditor`.
struct ScheduleView: View {
    /// The Days segments.
    enum DayChoice: Hashable { case weekdays, everyDay, custom }

    @ObservedObject var store: Store
    @StateObject private var model = ScheduleModel()

    private var config: Config? { store.snap.config }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                titleRow
                dayStrip
                    .padding(.top, WinMetrics.s24)
                timesSection
                daysSection
                limitsSection
                weekSection
            }
            .padding(.bottom, WinMetrics.canvasBottom)
        }
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.leading, WinMetrics.canvasLeft)
        .padding(.trailing, WinMetrics.canvasRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $model.addingTime) { addTimeSheet }
        .onAppear { model.refreshWeek(store) }
    }

    // MARK: Title row

    private var titleRow: some View {
        HStack(alignment: .top, spacing: WinMetrics.s16) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: WinMetrics.s12) {
                    Text("Schedule")
                        .font(.system(size: 24, weight: .bold))
                        .tracking(-0.4)
                        .foregroundStyle(WinTheme.text)
                        .frame(height: 32, alignment: .leading)
                    SavedStamp(shown: model.saved.shown)
                }
                Text(subline)
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                    .monospacedDigit()
                    .frame(height: 20, alignment: .leading)
            }
            Spacer(minLength: WinMetrics.s16)
            HStack(spacing: WinMetrics.s12) {
                Text("Pause sweeps")
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.muted)
                WinToggle(isOn: store.snap.paused) { store.togglePause() }
            }
            .frame(height: 32)
        }
    }

    /// "Three sweeps every weekday. Next at 7:00 PM, in 2 h 41 min." Each part is left out when it is unknown.
    private var subline: String {
        var parts: [String] = []
        if let config {
            let count = config.schedule.count
            let words = NumberFormatter.spelledOut(count)
            let days: String
            switch config.days {
            case .weekdays: days = "every weekday"
            case .all: days = "every day"
            case .custom: days = "on " + config.days.active.map { $0.name.capitalized }.joined(separator: ", ")
            }
            parts.append("\(words) sweeps \(days).")
        }
        if let next = store.snap.nextRun {
            let minutes = max(0, Int(next.timeIntervalSinceNow / 60))
            let away = minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
            parts.append("Next at \(next.formatted(date: .omitted, time: .shortened)), in \(away).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Day strip

    /// The strip: 72 pt track, the night bands, a pin per sweep time, the now line, and the ticks under it.
    private var dayStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            GeometryReader { geo in
                track(width: geo.size.width)
            }
            .frame(height: 72)
            ticks
                .frame(height: 16)
                .padding(.top, WinMetrics.s8)
        }
        .padding(.top, 20)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 14).fill(WinTheme.surface))
    }

    /// The hour ticks: the first starts at its position, the last ends at it, the rest are centred on it.
    private var ticks: some View {
        let labels: [(text: String, fraction: CGFloat)] = [("12 AM", 0), ("6 AM", 0.25), ("12 PM", 0.5), ("6 PM", 0.75), ("12 AM", 1)]
        return GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                ForEach(Array(labels.enumerated()), id: \.offset) { _, tick in
                    Text(tick.text)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                        .monospacedDigit()
                        .fixedSize()
                        .alignmentGuide(.leading) { d in
                            let shift = tick.fraction == 0 ? 0 : (tick.fraction == 1 ? d.width : d.width / 2)
                            return shift - tick.fraction * width
                        }
                }
            }
            .frame(width: width, alignment: .leading)
        }
    }

    /// Track geometry, from the mockup: rail at y 52, night bands and the now line at y 40 (26 tall), pins from y 22
    /// with a 12 pt dot centred on the rail.
    private func track(width: CGFloat) -> some View {
        let times = config?.schedule ?? []
        return ZStack(alignment: .topLeading) {
            Rectangle().fill(WinTheme.control).frame(width: width, height: 2).offset(y: 51)
            Rectangle().fill(WinTheme.night)
                .frame(width: width * 0.25, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(y: 40)
            Rectangle().fill(WinTheme.night)
                .frame(width: width * (1 - 22.0 / 24), height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .offset(x: width * 22.0 / 24, y: 40)
            Rectangle().fill(WinTheme.blue)
                .frame(width: 2, height: 26)
                .offset(x: fraction(of: Date()) * width - 1, y: 40)
            ForEach(times, id: \.self) { time in
                pin(time, width: width)
            }
        }
        .frame(width: width, height: 72, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture().onEnded { value in
                // A tap on a pin is not a new time.
                let nearPin = times.contains { abs(xPosition($0, width: width) - value.location.x) < 14 }
                guard !nearPin else { return }
                let minute = minuteOfDay(atX: value.location.x, width: width)
                model.addTime(store, hour: minute / 60, minute: minute % 60)
            }
        )
    }

    /// One sweep pin: a label above, the 2 pt amber pin and the dot on the rail. Dragging it moves the time; the new
    /// time saves when the drag ends.
    private func pin(_ time: ScheduleTime, width: CGFloat) -> some View {
        let x = xPosition(time, width: width)
        let moving = model.dragging == time
        return VStack(spacing: 0) {
            Text(clock(time))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WinTheme.text)
                .monospacedDigit()
                .frame(width: 80, height: 18)
            Rectangle().fill(WinTheme.amber).frame(width: 2, height: 24).padding(.top, 4)
            Circle().fill(WinTheme.amber).frame(width: 12, height: 12)
        }
        .frame(width: 80, height: 58, alignment: .top)
        .overlay(alignment: .top) {
            // The grab area is the pin itself, not the label.
            Color.clear
                .frame(width: 24, height: 58)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            model.dragging = time
                            model.dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            let target = min(max(x + value.translation.width, 0), width)
                            let minute = minuteOfDay(atX: target, width: width)
                            model.movePin(store, time, hour: minute / 60, minute: minute % 60)
                        }
                )
        }
        .offset(x: x - 40 + (moving ? model.dragOffset : 0), y: 0)
    }

    private func xPosition(_ time: ScheduleTime, width: CGFloat) -> CGFloat {
        CGFloat(time.hour * 60 + time.minute) / 1440 * width
    }

    private func fraction(of date: Date) -> CGFloat {
        let cal = Calendar.current
        let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        return CGFloat(minute) / 1440
    }

    private func minuteOfDay(atX x: CGFloat, width: CGFloat) -> Int {
        let minute = Int((x / max(width, 1)) * 1440)
        return min(max(minute, 0), 1439)
    }

    /// "7:00 AM", the chip and pin label.
    private func clock(_ time: ScheduleTime) -> String {
        let h12 = time.hour % 12 == 0 ? 12 : time.hour % 12
        return "\(h12):\(String(format: "%02d", time.minute)) \(time.hour < 12 ? "AM" : "PM")"
    }

    // MARK: Sections

    private var timesSection: some View {
        SettingRow(title: "Sweep times", detail: "Or click the day above.", error: model.rowErrors["time"]) {
            HStack(spacing: WinMetrics.s8) {
                ForEach(config?.schedule ?? [], id: \.self) { time in
                    chip(clock(time)) { model.removeTime(store, time) }
                }
                WinButton(title: "Add time…", style: .link) { model.addingTime = true }
                    .padding(.leading, WinMetrics.s4)
            }
        }
    }

    private var daysSection: some View {
        SettingRow(title: "Days", detail: "Sweeps skip the other days.", error: model.rowErrors["days"]) {
            VStack(alignment: .leading, spacing: WinMetrics.s12) {
                WinSegmented(
                    segments: [
                        .init(value: DayChoice.weekdays, title: "Weekdays"),
                        .init(value: DayChoice.everyDay, title: "Every day"),
                        .init(value: DayChoice.custom, title: "Custom…"),
                    ],
                    selected: config?.days.choice ?? .weekdays,
                    onSelect: { model.chooseDays(store, $0) }
                )
                if config?.days.choice == .custom {
                    HStack(spacing: WinMetrics.s4) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            dayToggle(day)
                        }
                    }
                }
            }
        }
    }

    /// A day toggle: 32 tall, the active fill when the day sweeps.
    private func dayToggle(_ day: Weekday) -> some View {
        let on = config?.days.active.contains(day) ?? false
        return Button {
            model.toggleDay(store, day)
        } label: {
            Text(day.name.capitalized)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? WinTheme.text : WinTheme.faint)
                .frame(width: 44, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(on ? WinTheme.active : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? WinTheme.segRing : WinTheme.control, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var limitsSection: some View {
        SettingRow(title: "Limits per sweep", detail: "Keep the token bill predictable.", error: model.rowErrors["limits"]) {
            HStack(alignment: .center, spacing: WinMetrics.s24) {
                stepper("PRs", value: config?.limits.maxPRsPerRun ?? 0, step: 1, low: 1, high: nil) { prs in
                    model.setLimits(store, prs: prs, lines: config?.limits.maxChangedLines ?? 0)
                }
                stepper("Lines per PR", value: config?.limits.maxChangedLines ?? 0, step: 500, low: 500,
                        high: ScheduleEditor.maxLinesPerPR) { lines in
                    model.setLimits(store, prs: config?.limits.maxPRsPerRun ?? 0, lines: lines)
                }
            }
        }
    }

    /// A stepper (base.css `.stp`): the label, then a 32 pt box with the value and − and + cells.
    private func stepper(_ label: String, value: Int, step: Int, low: Int, high: Int?,
                         onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: WinMetrics.s8) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(WinTheme.muted)
            HStack(spacing: 0) {
                Text(value.formatted(.number))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WinTheme.text)
                    .monospacedDigit()
                    .frame(minWidth: 56, alignment: .trailing)
                    .padding(.horizontal, WinMetrics.s12)
                stepCell("−") { onChange(max(low, value - step)) }
                stepCell("+") { onChange(min(high ?? Int.max, value + step)) }
            }
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8).fill(WinTheme.surface))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(WinTheme.control, lineWidth: 1))
        }
    }

    private func stepCell(_ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(glyph)
                .font(.system(size: 13))
                .foregroundStyle(WinTheme.muted)
                .frame(width: 28, height: 32)
                .overlay(alignment: .leading) {
                    Rectangle().fill(WinTheme.control).frame(width: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var weekSection: some View {
        SettingRow(title: "This week", detail: "Since Monday.", error: nil) {
            HStack(alignment: .top, spacing: WinMetrics.s32) {
                kpi(model.week.reviews, "reviews")
                kpi(model.week.needChanges, "need changes")
                kpi(model.week.tokens, "tokens", compact: true)
            }
        }
    }

    private func kpi(_ value: Int, _ label: String, compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(compact ? compactTokens(value) : value.formatted(.number))
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(WinTheme.text)
                .monospacedDigit()
                .frame(height: 32, alignment: .leading)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.faint)
                .frame(height: 16, alignment: .leading)
        }
    }

    /// A chip (base.css `.chip`): 28 tall, raised fill, a × that removes it.
    private func chip(_ text: String, remove: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(WinTheme.text)
                .monospacedDigit()
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WinTheme.faint)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, WinMetrics.s12)
        .frame(height: 28)
        .background(Capsule().fill(WinTheme.raised))
    }

    // MARK: Add time sheet

    private var addTimeSheet: some View {
        VStack(alignment: .leading, spacing: WinMetrics.s16) {
            Text("Add a sweep time")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WinTheme.text)
            DatePicker("Time", selection: $model.newTime, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.field)
            if let error = model.rowErrors["time"] {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.amberInk)
            }
            HStack {
                Spacer()
                WinButton(title: "Cancel", style: .outline, small: true) { model.addingTime = false }
                WinButton(title: "Add", style: .primary, small: true) { model.addFromSheet(store) }
            }
        }
        .padding(WinMetrics.s24)
        .frame(width: 320)
    }
}

/// The Schedule section's state: the day's drag, the sheet's time, this week's counts, and the Saved stamp. Each
/// change goes through `commit`, which saves the config and reinstalls the job, or writes nothing and shows a message.
@MainActor
final class ScheduleModel: ObservableObject {
    @Published var addingTime = false
    @Published var newTime = Date()
    @Published var rowErrors: [String: String] = [:]
    @Published var dragging: ScheduleTime?
    @Published var dragOffset: CGFloat = 0
    @Published var week = WeekStats()
    let saved = SavedFlash()

    func refreshWeek(_ store: Store) {
        let runs = RunStore(paths: store.paths).loadAll()
        week = WeekStats.compute(runs: runs, since: WeekStats.weekStart(of: Date()) ?? .distantPast)
    }

    func addTime(_ store: Store, hour: Int, minute: Int) {
        commit("time", store) { try ScheduleEditor.addTime($0, hour: hour, minute: minute) }
    }

    func addFromSheet(_ store: Store) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: newTime)
        let minute = cal.component(.minute, from: newTime)
        if commit("time", store, { try ScheduleEditor.addTime($0, hour: hour, minute: minute) }) {
            addingTime = false
        }
    }

    func removeTime(_ store: Store, _ time: ScheduleTime) {
        commit("time", store) { try ScheduleEditor.removeTime($0, time) }
    }

    func movePin(_ store: Store, _ time: ScheduleTime, hour: Int, minute: Int) {
        dragging = nil
        dragOffset = 0
        commit("time", store) { try ScheduleEditor.moveTime($0, from: time, hour: hour, minute: minute) }
    }

    func chooseDays(_ store: Store, _ choice: ScheduleView.DayChoice) {
        commit("days", store) { config in
            switch choice {
            case .weekdays: return try ScheduleEditor.setDays(config, .weekdays)
            case .everyDay: return try ScheduleEditor.setDays(config, .all)
            case .custom: return try ScheduleEditor.setDays(config, .custom(Set(config.days.active)))
            }
        }
    }

    /// Turns one day on or off in a custom week. The last day on cannot go off.
    func toggleDay(_ store: Store, _ day: Weekday) {
        commit("days", store) { config in
            var set = Set(config.days.active)
            if set.contains(day) { set.remove(day) } else { set.insert(day) }
            return try ScheduleEditor.setDays(config, .custom(set))
        }
    }

    func setLimits(_ store: Store, prs: Int, lines: Int) {
        commit("limits", store) { try ScheduleEditor.setLimits($0, prs: prs, lines: lines) }
    }

    /// Applies one edit to the saved config and saves it. On success the store reloads, the stamp shows and the
    /// counts refresh. On failure the message goes to `row` and nothing is written.
    @discardableResult
    private func commit(_ row: String, _ store: Store, _ change: (Config) throws -> Config) -> Bool {
        guard let config = store.snap.config else {
            rowErrors[row] = "No config yet. Run glidepath init."
            return false
        }
        do {
            let next = try change(config)
            try ScheduleEditor.save(next, paths: store.paths)
            rowErrors[row] = nil
            saved.flash()
            store.reload()
            refreshWeek(store)
            return true
        } catch let error as ConfigError {
            rowErrors[row] = error.message
        } catch {
            rowErrors[row] = "Could not save: \(error.localizedDescription)"
        }
        return false
    }
}

extension NumberFormatter {
    /// "three" for 3, sentence-cased as "Three". Digits for anything the spell-out cannot name.
    static func spelledOut(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        guard let word = f.string(from: NSNumber(value: n)) else { return "\(n)" }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
