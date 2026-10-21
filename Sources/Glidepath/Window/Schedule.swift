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
    @FocusState private var stripFocused: Bool

    private var config: Config? { store.snap.config }

    var body: some View {
        WinScroll {
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

    // MARK: Keys

    /// On the day strip: ← → select the previous or next pin; ↑ ↓ move it 15 min later or earlier, ⇧ or ⌥ for the
    /// hour and the quarter hour as noted; ⌫ deletes it; ⌘Z undoes this session's schedule changes.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let mods = ShortcutModifiers(press.modifiers)
        if mods == [.command], press.characters == "z" {
            guard !TextFocus.isEditing else { return .ignored }
            model.undo(store)
            return .handled
        }
        guard !TextFocus.isEditing else { return .ignored }
        switch press.key {
        case .leftArrow where mods.isEmpty:
            model.select(-1, times: displayed)
        case .rightArrow where mods.isEmpty:
            model.select(1, times: displayed)
        case .leftArrow where mods == [.option]:
            model.nudge(store, by: -PinNudge.quarter)
        case .rightArrow where mods == [.option]:
            model.nudge(store, by: PinNudge.quarter)
        case .upArrow where mods.isEmpty:
            model.nudge(store, by: PinNudge.quarter)
        case .downArrow where mods.isEmpty:
            model.nudge(store, by: -PinNudge.quarter)
        case .upArrow where mods == [.shift]:
            model.nudge(store, by: 60)
        case .downArrow where mods == [.shift]:
            model.nudge(store, by: -60)
        case .delete where mods.isEmpty:
            model.deletePin(store)
        default:
            return .ignored
        }
        return .handled
    }

    /// The pins as the strip shows them, with a pin mid-nudge already at its new time.
    private var displayed: [ScheduleTime] { model.displayedTimes(config) }

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
            parts.append("Next at \(HeaderCopy.clock(next)), in \(HeaderCopy.untilText(next, store.snap.now ?? Date())).")
        }
        return parts.joined(separator: " ")
    }

    // MARK: Day strip

    private var dayStrip: some View {
        DayStrip(
            times: displayed,
            now: store.snap.now,
            onAdd: { minute in model.addTime(store, hour: minute / 60, minute: minute % 60) },
            onMove: { time, minute in model.movePin(store, time, hour: minute / 60, minute: minute % 60) },
            selected: model.selectedPin
        )
        .focusable()
        .focused($stripFocused)
        .onKeyPress(phases: .down) { handleKey($0) }
    }

    // MARK: Sections

    private var timesSection: some View {
        SettingRow(title: "Sweep times", detail: "Or click the day above.", error: model.rowErrors["time"]) {
            HStack(spacing: WinMetrics.s8) {
                ForEach(config?.schedule ?? [], id: \.self) { time in
                    chip(time.clock) { model.removeTime(store, time) }
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
    /// The pin the keyboard has selected.
    @Published var selectedPin: ScheduleTime?
    /// A pin being nudged: its time on disk, and where it is now. Saved once the keys go quiet.
    @Published private(set) var draft: (from: ScheduleTime, to: ScheduleTime)?
    /// The schedules before this session's changes, newest last. ⌘Z pops one.
    private var history: [[ScheduleTime]] = []
    private var saveTask: Task<Void, Never>?
    @Published var newTime = Date()
    @Published var rowErrors: [String: String] = [:]
    @Published var week = WeekStats()
    let saved = SavedFlash()

    func refreshWeek(_ store: Store) {
        let runs = store.allRuns()
        week = WeekStats.compute(runs: runs, since: WeekStats.weekStart(of: Date()) ?? .distantPast)
    }

    func addTime(_ store: Store, hour: Int, minute: Int) {
        commit("time", store) { try ScheduleEditor.addTime($0, hour: hour, minute: minute) }
    }

    func addFromSheet(_ store: Store) {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: newTime)
        let minute = cal.component(.minute, from: newTime)
        commit("time", store, then: { [self] ok in if ok { addingTime = false } }) {
            try ScheduleEditor.addTime($0, hour: hour, minute: minute)
        }
    }

    func removeTime(_ store: Store, _ time: ScheduleTime) {
        commit("time", store) { try ScheduleEditor.removeTime($0, time) }
    }

    /// The sweep times as the strip shows them: the saved times, with a pin mid-nudge at its new time.
    func displayedTimes(_ config: Config?) -> [ScheduleTime] {
        let saved = config?.schedule ?? []
        guard let draft else { return saved }
        return saved.map { $0 == draft.from ? draft.to : $0 }
    }

    /// Moves the selected pin by `minutes`. Each press moves the pin on screen at once; the save waits 500 ms for the
    /// keys to go quiet, so a burst of presses is one write, and ⌘Z undoes the whole burst.
    func nudge(_ store: Store, by minutes: Int) {
        guard let config = store.snap.config, let current = draft?.to ?? selectedPin else { return }
        let origin = draft?.from ?? current
        guard let target = PinNudge.target(from: current, by: minutes, among: displayedTimes(config)) else { return }
        if draft == nil { history.append(config.schedule) }
        draft = (from: origin, to: target)
        selectedPin = target
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self, let d = self.draft else { return }
            self.commit("time", store, then: { [weak self] ok in
                self?.draft = nil
                if !ok { self?.history.removeLast() }
            }) {
                try ScheduleEditor.moveTime($0, from: d.from, hour: d.to.hour, minute: d.to.minute)
            }
        }
    }

    /// Selects the pin `step` places along from the selection. With none, → takes the first and ← the last.
    func select(_ step: Int, times: [ScheduleTime]) {
        let sorted = times.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        guard !sorted.isEmpty else { return }
        guard let current = selectedPin, let index = sorted.firstIndex(of: current) else {
            selectedPin = step > 0 ? sorted.first : sorted.last
            return
        }
        selectedPin = sorted[min(max(index + step, 0), sorted.count - 1)]
    }

    /// Deletes the selected pin. The selection moves to its neighbour. ⌘Z brings it back.
    func deletePin(_ store: Store) {
        guard let config = store.snap.config, let pin = selectedPin, config.schedule.contains(pin) else { return }
        let sorted = config.schedule.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
        let index = sorted.firstIndex(of: pin) ?? 0
        let neighbour = index + 1 < sorted.count ? sorted[index + 1] : (index > 0 ? sorted[index - 1] : nil)
        history.append(config.schedule)
        commit("time", store, then: { [weak self] ok in
            if ok { self?.selectedPin = neighbour } else { self?.history.removeLast() }
        }) { try ScheduleEditor.removeTime($0, pin) }
    }

    /// Restores the schedule from before the last change this session.
    func undo(_ store: Store) {
        guard let previous = history.popLast() else { return }
        commit("time", store) { try ScheduleEditor.setSchedule($0, previous) }
    }

    func movePin(_ store: Store, _ time: ScheduleTime, hour: Int, minute: Int) {
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

    /// Applies one edit to config.toml as it is on disk now, and saves it off the main actor. On success the store
    /// reloads, the stamp shows and the counts refresh. On failure the message goes to `row` and nothing is written.
    /// The store reloads either way. `done` gets the outcome.
    private func commit(_ row: String, _ store: Store, then done: @escaping (Bool) -> Void = { _ in },
                        _ change: @escaping @Sendable (Config) throws -> Config) {
        let paths = store.paths
        Task {
            let ok: Bool
            do {
                // A deferred reinstall needs no call here: the store's reload runs the reconcile once the lock frees.
                _ = try await ConfigWriter.shared.apply(paths: paths, change: change) {
                    try ScheduleEditor.save($0, paths: paths)
                }
                rowErrors[row] = nil
                saved.flash()
                ok = true
            } catch let error as ConfigError {
                rowErrors[row] = error.message
                ok = false
            } catch {
                rowErrors[row] = "Could not save: \(error.localizedDescription)"
                ok = false
            }
            store.reload()
            if ok { refreshWeek(store) }
            done(ok)
        }
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
