import SwiftUI

/// The menu bar popover (spec §4.2): is it fine, and does it need me? The glide line on top, the status sentence with
/// one control, up to four Needs-you rows that only open the window, what happened since the last look, and the footer.
/// You decide in the window, where you can read what you approve, so the rows have no actions.
struct MenuPopover: View {
    @ObservedObject var store: Store
    /// Closes the popover; the hosting status item sets it.
    var close: () -> Void = {}

    var body: some View {
        PopoverContent(state: store.status, needs: store.needsYou,
                       since: store.sinceLastLooked.map(Copy.since) ?? "",
                       autopilot: store.snap.config?.tend.autopilot ?? false,
                       paused: store.snap.paused,
                       act: act)
            .background(keys)
    }

    private func act(_ action: MenuAction) {
        MenuActions.perform(action, store: store)
        if action.closesPopover { close() }
    }

    /// The popover's shortcuts (the Shortcuts table's popover scope): ⌘R check now, ⌘. stop, ⌘O the window, ⌘,
    /// Settings. Esc is the popover's own.
    private var keys: some View {
        ZStack {
            Button("") { if MenuActions.canCheck(store.snap) { act(.checkNow) } }.keyboardShortcut("r")
            Button("") { if case .checking = store.status { act(.stop) } }.keyboardShortcut(".")
            Button("") { act(.openWindow) }.keyboardShortcut("o")
            Button("") { act(.settings) }.keyboardShortcut(",")
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}

/// What the popover's controls ask for. One place runs them, for the popover, the status item menu and the Dock menu.
enum MenuAction: Equatable {
    case checkNow, stop, resume, adjust, openWindow, settings
    case fix(FixAction)
    case pause(until: Date?)
    case open(Need)

    /// Anything that brings up a window or another app closes the popover.
    var closesPopover: Bool {
        switch self {
        case .checkNow, .stop, .resume, .pause: return false
        case .adjust, .openWindow, .settings, .fix, .open: return true
        }
    }

    /// The status sentence's control.
    static func control(for state: GlideState) -> MenuAction {
        switch state {
        case .quiet: return .checkNow
        case .checking: return .stop
        case .needs: return .openWindow
        case .paused: return .resume
        case .problem(_, let fix): return .fix(fix)
        case .holdingBack: return .adjust
        }
    }
}

@MainActor
enum MenuActions {
    static func perform(_ action: MenuAction, store: Store) {
        guard !store.isFixture else { return }
        let router = WindowRouter.shared
        switch action {
        case .checkNow: Confirm.run(store)
        case .stop: store.stopAll()
        case .resume: store.resume()
        case .pause(let until): store.pause(until: until)
        case .openWindow: router.open(nil)
        // The schedule and the usage reserve live in Settings until phase 5 gives them their own window.
        case .adjust, .settings: router.open(.settings)
        case .fix(.setUp): router.openOnboarding()
        case .fix(.installSchedule): router.open(.schedule)
        case .fix(.signIn): FixInTerminal.open(script: "#!/bin/zsh\ngh auth login\n")
        case .fix(.showLog): store.openLog()
        case .open(let need):
            // ponytail: lands on the nearest 1.10 screen; phase 4 opens the new inspector on the PR.
            switch need.kind {
            case .reviewReady, .tooLarge: router.openReview(need.prID)
            default: router.open(.approach)
            }
        }
    }

    /// Check now is offered only when a check could start.
    static func canCheck(_ snap: Snapshot) -> Bool {
        !snap.running && !snap.dryRunning && !snap.paused && snap.jobInstalled
    }

    /// The Pause choices: an hour, tomorrow at 9:00, or until the user resumes.
    static func pauseChoices(now: Date = Date(), calendar: Calendar = .current) -> [(title: String, until: Date?)] {
        let start = calendar.startOfDay(for: now)
        let nine = calendar.date(byAdding: .day, value: 1, to: start).flatMap {
            calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0)
        }
        var out: [(String, Date?)] = [(Copy.pauseOneHour, now.addingTimeInterval(3600))]
        if let nine { out.append((Copy.pauseUntilTomorrow(nine, calendar: calendar), nine)) }
        out.append((Copy.pauseUntilResume, nil))
        return out
    }
}

/// The popover drawn from plain values, so the kit gallery renders every state without a store.
struct PopoverContent: View {
    static let width: CGFloat = 360
    static let maxHeight: CGFloat = 520
    static let maxRows = 4

    let state: GlideState
    let needs: [Need]
    let since: String
    let autopilot: Bool
    let paused: Bool
    let act: (MenuAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatusHeader(state: state, size: .popover, onFix: { act(MenuAction.control(for: state)) }) {
                Button(Copy.statusButton(state)) { act(MenuAction.control(for: state)) }
                    .glassButtonStyle()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 12)

            if !needs.isEmpty {
                VStack(spacing: 2) {
                    ForEach(needs.prefix(Self.maxRows)) { need in
                        PopoverRow(need: need) { act(.open(need)) }
                    }
                    if needs.count > Self.maxRows {
                        Text(Copy.more(needs.count - Self.maxRows))
                            .font(Ladder.secondary)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }

            if !since.isEmpty {
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Copy.sinceYouLastLooked).font(Ladder.secondary).foregroundStyle(.secondary)
                    Text(since).font(Ladder.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }

            Divider().padding(.horizontal, 16)
            footer
        }
        .frame(width: Self.width)
        .frame(maxHeight: Self.maxHeight, alignment: .top)
        // Smoked: the popover's own glass stays, darkened so the text reads on any wallpaper.
        .background(Color.black.opacity(0.45).ignoresSafeArea())
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(Copy.mode(autopilot: autopilot), systemImage: autopilot ? "airplane" : "hand.raised")
                .font(Ladder.secondary)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                if paused {
                    Button(Copy.resume) { act(.resume) }
                    Divider()
                }
                ForEach(Array(MenuActions.pauseChoices().enumerated()), id: \.offset) { _, choice in
                    Button(choice.title) { act(.pause(until: choice.until)) }
                }
            } label: {
                // Plain style keeps the label at full contrast; a bordered menu button reads as disabled here.
                HStack(spacing: 4) {
                    Text(Copy.pause)
                    Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                }
                .font(Ladder.secondary)
                .foregroundStyle(.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .glassCapsule(interactive: true)
            Button { act(.openWindow) } label: {
                Image(systemName: "macwindow")
                    .font(Ladder.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .glassCapsule(interactive: true)
            .help(Copy.openGlidepath)
            .accessibilityLabel(Copy.openGlidepath)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

/// One Needs-you row: who, the title, what it needs in amber, and where. Clicking opens the window on the PR.
private struct PopoverRow: View {
    let need: Need
    let action: () -> Void
    @StateObject private var hover = Hover()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let author = need.author {
                    AvatarView(login: author, size: 26)
                } else {
                    // The user's own PR: no login to fetch.
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(.white.opacity(0.1), in: Circle())
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(need.title).font(Ladder.body).lineLimit(1)
                    Text("\(Text(Copy.label(need.kind)).foregroundStyle(Color.amber))  ·  \(need.repo) #\(String(need.number))")
                        .font(Ladder.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.white.opacity(hover.on ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hover.on = $0 }
        .accessibilityElement(children: .combine)
    }
}

final class Hover: ObservableObject {
    @Published var on = false
}
