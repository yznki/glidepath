import SwiftUI

struct SettingsView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        TabView(selection: $store.settingsPane) {
            Tab("General", systemImage: "gearshape", value: SettingsPane.general) { GeneralPane() }
            Tab("Schedule", systemImage: "calendar.badge.clock", value: SettingsPane.schedule) { SchedulePane() }
            Tab("Behaviour", systemImage: "hand.raised", value: SettingsPane.behaviour) { BehaviourPane() }
            Tab("Advanced", systemImage: "wrench.and.screwdriver", value: SettingsPane.advanced) { AdvancedPane() }
        }
        .frame(width: 520)
    }
}

struct GeneralPane: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("Open at login", isOn: $store.openAtLogin)
                Toggle("Show in menu bar", isOn: $store.showInMenuBar)
                Picker("Notifications", selection: $store.notifications) {
                    ForEach(["Needs you only", "Everything", "Off"], id: \.self) { Text($0) }
                }
            }
            Section {
                LabeledContent {
                    Button("Change…") {}
                } label: {
                    Text("Claude account")
                    Text("Signed in · Sager Team")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 250)
    }
}

struct SchedulePane: View {
    @Environment(Store.self) private var store
    private let dayNames = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Check", selection: $store.preset) {
                    ForEach(["Workday", "Every 2 hours", "Once a day", "Custom"], id: \.self) { Text($0) }
                }
                .onChange(of: store.preset) { _, p in applyPreset(p) }
                if store.preset == "Custom" { LabeledContent("At") {
                    HStack(spacing: 6) {
                        ForEach(store.times.indices, id: \.self) { i in
                            DatePicker("Time \(i + 1)", selection: $store.times[i], displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        if store.preset == "Custom" {
                            Button("Add Time", systemImage: "plus") { store.times.append(Store.time(15)) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                        }
                    }
                } }
                LabeledContent("On") {
                    HStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { i in
                            Toggle(dayNames[i], isOn: $store.days[i])
                                .toggleStyle(.button)
                                .frame(width: 30)
                        }
                    }
                }
            } header: {
                Text(sentence)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .textCase(nil)
            }
            Section("Quiet hours") {
                DatePicker("From", selection: $store.quietFrom, displayedComponents: .hourAndMinute)
                DatePicker("To", selection: $store.quietTo, displayedComponents: .hourAndMinute)
                Toggle("Quiet all weekend", isOn: $store.quietWeekend)
            }
            Section {
                LabeledContent {
                    Slider(value: $store.reserve, in: 0...50, step: 5) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("0%")
                    } maximumValueLabel: {
                        Text("50%")
                    }
                    .frame(width: 200)
                } label: {
                    Text("Keep for myself")
                    Text("Glidepath stops at \(100 - Int(store.reserve))% used.")
                }
                UsageGauge()
            } header: {
                Text("Claude usage")
            } footer: {
                Text("Heavy work waits for quiet hours. Checks never run while you're paused.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(height: store.preset == "Custom" ? 610 : 560)
    }

    private var sentence: String {
        let f = Date.FormatStyle().hour(.defaultDigits(amPM: .omitted)).minute()
        let ts = store.times.sorted().map { $0.formatted(f) }
        let list = ts.count > 1 ? ts.dropLast().joined(separator: ", ") + " and " + ts.last! : (ts.first ?? "")
        let weekdays = store.days == [true, true, true, true, true, false, false]
        let every = store.days.allSatisfy { $0 }
        return "\(weekdays ? "Weekdays" : every ? "Every day" : "Selected days") at \(list)"
    }

    private func applyPreset(_ p: String) {
        switch p {
        case "Workday": store.times = [9, 13, 17].map { Store.time($0) }
        case "Every 2 hours": store.times = [9, 11, 13, 15, 17].map { Store.time($0) }
        case "Once a day": store.times = [Store.time(9)]
        default: break
        }
    }
}

struct BehaviourPane: View {
    @Environment(Store.self) private var store
    @State private var confirming = false

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Picker("Mode", selection: Binding(get: { confirming ? .autopilot : store.mode }, set: { m in
                    if m == .autopilot && store.mode == .askFirst { withAnimation { confirming = true } }
                    else { withAnimation { confirming = false; store.mode = m } }
                })) {
                    Text("Ask first").tag(Mode.askFirst)
                    Text("Autopilot").tag(Mode.autopilot)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.extraLarge)
                .frame(maxWidth: .infinity)

                Text(explainer)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if confirming {
                    HStack {
                        Text("Autopilot acts as you on GitHub without asking.")
                            .font(.callout)
                        Spacer()
                        Button("Cancel") { withAnimation { confirming = false } }
                        HoldButton(title: "Turn on Autopilot", hint: "Hold to turn on") {
                            withAnimation { store.mode = .autopilot; confirming = false }
                        }
                    }
                }
            }
            Section {
                if store.mode == .askFirst {
                    Picker("What to post", selection: $store.postAs) {
                        Text("Comment").tag("Comment")
                        Text("Full review").tag("Full review")
                    }
                }
                Picker("Review strictness", selection: $store.strictness) {
                    ForEach(["Relaxed", "Balanced", "Strict"], id: \.self) { Text($0) }
                }
                Picker("Skip PRs over", selection: $store.sizeLimit) {
                    ForEach([400, 800, 1200, 2000, 5000], id: \.self) { Text("\($0.formatted()) lines").tag($0) }
                    Divider()
                    Text("No limit").tag(Int.max)
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: confirming ? 340 : 280)
    }

    private var explainer: String {
        (store.mode == .autopilot || confirming)
            ? "Autopilot posts reviews, pushes CI fixes, sends replies and merges your PRs when they're ready, without asking. Everything still shows up in Activity."
            : "Glidepath asks before anything goes to GitHub. Reviews, fixes, replies and merges wait in your Inbox until you hold to send them."
    }
}

struct AdvancedPane: View {
    @Environment(Store.self) private var store
    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                LabeledContent("Config file") {
                    Button("Show in Finder") {}
                }
                LabeledContent("Logs") {
                    Button("Open Logs") {}
                }
            }
            Section {
                Picker("Model", selection: $store.model) {
                    ForEach(["Sonnet", "Opus"], id: \.self) { Text($0) }
                }
                LabeledContent("Budget per check") {
                    TextField("Budget", value: $store.budget, format: .currency(code: "USD"))
                        .labelsHidden().multilineTextAlignment(.trailing).frame(width: 80)
                }
                SecureField("Linear key", text: $store.linearKey, prompt: Text("Not set"))
            }
            Section {
                LabeledContent {
                    Button("Reset…") {}
                } label: {
                    Text("Reset Glidepath")
                    Text("Puts every setting back. Your repos stay.")
                }
                LabeledContent {
                    Button("Uninstall…", role: .destructive) {}
                } label: {
                    Text("Uninstall")
                    Text("Removes Glidepath, its settings and logs.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(height: 380)
    }
}

/// Current Claude usage against the reserve: the bar fills with what's used, a tick marks where Glidepath stops.
struct UsageGauge: View {
    @Environment(Store.self) private var store
    var body: some View {
        let stop = 100 - store.reserve
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Used \(Int(store.usage))% of this 5-hour window")
                Spacer()
                Text("\(Int(store.reserve))% kept for you").foregroundStyle(.secondary)
            }
            Gauge(value: store.usage, in: 0...100) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .labelsHidden()
                .tint(Color.graphite)
                .overlay {
                    // Where Glidepath stops: the reserve starts here.
                    GeometryReader { g in
                        Capsule().fill(.white)
                            .frame(width: 2, height: g.size.height + 8)
                            .position(x: g.size.width * stop / 100, y: g.size.height / 2)
                    }
                    .allowsHitTesting(false)
                }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(store.usage)) percent used, Glidepath stops at \(Int(stop)) percent")
        .padding(.vertical, 2)
    }
}
