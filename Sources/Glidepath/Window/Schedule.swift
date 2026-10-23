import SwiftUI
import Combine

/// The Schedule section (1.3 prototype `.sched`): a 24 h dial for the sweep window and interval, presets, day pills,
/// the numbers under them, the next eight sweeps, and the pause control. Changes save 0.4 s after the last one through
/// `ScheduleEditor`, which reinstalls the launchd job.
struct ScheduleView: View {
    @ObservedObject var store: Store
    @StateObject private var model: ScheduleModel
    @Environment(\.offscreenRender) private var offscreen
    @AppStorage("signalColour") private var signalKey = "amber"
    @AppStorage("motion") private var motion = "full"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reduced: Bool { Motion.reduced(reduceMotion) }
    private var signal: Color { Gotham.signal(signalKey) }
    private static let letters = ["M", "T", "W", "T", "F", "S", "S"]

    /// The model starts from the config and the run history, not from onAppear, since snapshot rendering never fires onAppear.
    init(store: Store) {
        self.store = store
        let model = ScheduleModel(config: store.snap.config,
                                  sweepTokens: DialStats.sweepTokens(store.allRuns(), now: Date()))
        model.dial.onChange = { [weak model] in model?.changed(store) }
        _model = StateObject(wrappedValue: model)
    }

    var body: some View {
        // WinScroll, not ScrollView: snapshot rendering draws ScrollView blank.
        WinScroll {
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
            model.loadHistory(store.allRuns())
        }
        .onChange(of: store.snap.schedule) { _, _ in model.sync(store.snap.config) }
        .onChange(of: store.snap.config?.days) { _, _ in model.sync(store.snap.config) }
        .onDisappear { model.flush(store) }
    }

    // MARK: Header

    private var header: some View {
        SnapshotTimeline(schedule: .periodic(from: .now, by: 30)) { date in
            let next = DialUpcoming.next(1, after: date, times: model.dial.times, days: model.dial.scheduleDays).first
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Schedule")
                            .font(.system(size: 24, weight: .semibold))
                            .tracking(-0.4)
                            .foregroundStyle(Gotham.fg)
                        SavedNote(saved: model.saved)
                    }
                    Text(status(now: date, next: next))
                        .monospacedDigit()
                        .cap()
                }
                Spacer(minLength: 16)
                pauseControl(now: date)
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
        ScheduleDialView(dial: model.dial, reduced: reduced, signal: signal, error: model.error)
    }

    // MARK: Side column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Presets").cap()
            PresetGrid(dial: model.dial, reduced: reduced)
                .padding(.top, 12)
            Text("Days").cap().padding(.top, 26)
            DayPills(dial: model.dial, reduced: reduced).padding(.top, 12)
            stats.padding(.top, 26)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Sweeps a day, a week, and the month's tokens estimate. No estimate until three sweeps have finished ("—").
    /// Over the budget (when one is set) the last one turns into the signal colour.
    private var stats: some View {
        let perDay = model.dial.times.count
        let perWeek = perDay * model.dial.days.count
        let tokens = model.sweepTokens.map { DialStats.tokensPerMonth(perWeek: perWeek, perSweep: $0) }
        let over = tokens.map { DialStats.overBudget(tokens: $0, budget: store.snap.config?.monthlyTokens ?? 0) } ?? false
        return HStack(alignment: .top, spacing: 26) {
            stat("\(perDay)", "Sweeps a day", warn: false)
            stat("\(perWeek)", "A week", warn: false)
            if let tokens {
                stat("~" + DialFormat.compact(tokens), over ? "Over budget" : "Tokens a month", warn: over)
            } else {
                stat("—", "Tokens a month · after 3 sweeps", warn: false)
            }
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
        SnapshotTimeline(schedule: .periodic(from: .now, by: 30)) { date in
            let dates = DialUpcoming.next(8, after: date, times: model.dial.times, days: model.dial.scheduleDays)
            VStack(alignment: .leading, spacing: 14) {
                Text("Upcoming").cap()
                if dates.isEmpty {
                    Text("No sweeps scheduled. Pick at least one day.").cap()
                } else {
                    let row = HStack(alignment: .top, spacing: 0) {
                        ForEach(Array(dates.enumerated()), id: \.offset) { index, tick in
                            upcomingTick(tick, first: index == 0, now: date)
                        }
                    }
                    .background(alignment: .topLeading) {
                        Rectangle().fill(Gotham.edge).frame(height: 1).padding(.top, 4)
                    }
                    // Offscreen a horizontal ScrollView draws blank, so the row is drawn as it is.
                    if offscreen {
                        row
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) { row }
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

/// The "Saved" stamp. Observes `SavedFlash` directly, since the model does not forward its changes.
private struct SavedNote: View {
    @ObservedObject var saved: SavedFlash

    var body: some View {
        Text("Saved")
            .cap()
            .opacity(saved.shown ? 1 : 0)
    }
}

// MARK: - Model

/// The Schedule section's state: the dial (`DialEditor`), the pause and the debounced save. Every dial change reaches
/// `changed`, which marks the model dirty; `save` writes the times and days through `ScheduleEditor` and reinstalls the job.
@MainActor
final class ScheduleModel: ObservableObject {
    /// The dial's window, days and custom times.
    let dial = DialEditor()
    /// The last save's error, shown under the dial.
    @Published private(set) var error: String?
    /// Mean tokens per finished sweep over the last 30 days, or nil until there are enough to measure.
    @Published private(set) var sweepTokens: Int?
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
    private var cancellables = Set<AnyCancellable>()

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

    init(config: Config? = nil, sweepTokens: Int? = nil) {
        self.sweepTokens = sweepTokens
        // The dial's changes re-render the views that watch this model.
        dial.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        sync(config)
    }

    /// Re-reads the run history for the estimate. Called when the section appears.
    func loadHistory(_ runs: [RunState]) {
        sweepTokens = DialStats.sweepTokens(runs, now: Date())
    }

    /// Takes the config's schedule when it differs from what this model last saved or loaded.
    func sync(_ config: Config?) {
        guard let config, !dirty, !saveInFlight else { return }
        if let synced, synced.times == config.schedule, synced.days == config.days { return }
        synced = (config.schedule, config.days)
        dial.load(times: config.schedule, days: config.days)
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
                let until = DialPause.tomorrow(now: now, times: dial.times, days: dial.scheduleDays)
                try Pause.set(true, store.paths, until: until ?? now.addingTimeInterval(86400))
            }
            error = nil
        } catch {
            self.error = "Pause: \(error.localizedDescription)"
        }
        store.reload()
    }

    // MARK: Saving

    /// Marks a change and saves 0.4 s after the last one. The dial calls this on each of its changes.
    func changed(_ store: Store) {
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
        let times = dial.times
        let days = dial.scheduleDays
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
