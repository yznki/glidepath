import SwiftUI
import AppKit

/// View-local state. SwiftUI's state wrappers are macros in the SDK and Command Line Tools cannot load
/// their plugins, so views keep their few mutable values in observable objects instead.
final class PopoverModel: ObservableObject {
    init(openID: String? = nil) { self.openID = openID }

    @Published var loginOn = false
    /// The card that is open (its strip id). An open card springs to the top; the others pile below it.
    @Published var openID: String?
    /// The open card's height, measured from its content and never under `StackGeometry.open`.
    @Published var openHeight = StackGeometry.open
    /// The card the pointer or the keyboard is on. It lifts, and the cards below it step down.
    @Published var highlight: String?
    /// Horizontal drag offset of each card being swiped.
    @Published var drag: [String: CGFloat] = [:]
    /// Cards swiped off to discard: they fade before the discard runs.
    @Published var gone: Set<String> = []
}

/// Holds the fill of the round run button while it is held down.
final class FillModel: ObservableObject {
    @Published var level: CGFloat = 0
}

/// The stack's geometry, from the prototype's `layout()`, and which cards it takes. Points.
enum StackGeometry {
    static let width: CGFloat = 360
    static let closed: CGFloat = 64
    /// The least an open card is. It grows to fit its content (`PopoverModel.openHeight`).
    static let open: CGFloat = 232
    static let pad: CGFloat = 12
    /// Cards sit 12 pt in from each side of the popover.
    static let inset: CGFloat = 12
    static let cardWidth: CGFloat = width - 2 * inset
    /// Most cards on the stack. Past it, one "+N more" strip stands at the bottom.
    static let maxCards = 6
    /// Most cards that peek below an open card.
    static let maxPiled = 3

    /// The header is 66 pt, plus 22 pt for the caption when there is one.
    static func head(caption: Bool) -> CGFloat { caption ? 88 : 66 }

    /// Overlap between closed cards: 56 pt at most, less when the stack is tall.
    static func step(_ n: Int) -> CGFloat { n > 1 ? min(56, (420 - closed) / CGFloat(n - 1)) : 0 }

    /// The "All clear" block when no card shows: glider and label, compact.
    static let emptyHeight: CGFloat = 96

    /// The stack's height from what it draws: `n` closed rows, or with a card open its height and the `piled` cards
    /// under it.
    static func height(_ n: Int, head: CGFloat, openHeight: CGFloat?, piled: Int) -> CGFloat {
        if let openHeight {
            return head + openHeight + (piled > 0 ? 14 + CGFloat(piled - 1) * 7 + closed : 0) + pad
        }
        return head + (n > 0 ? CGFloat(n - 1) * step(n) + closed : emptyHeight) + pad
    }

    /// Running first, then held drafts, changes, approved, queued while a sweep runs, and skipped last. Ties keep the
    /// order the strips came in.
    static func ordered(_ all: [Strip], running: Bool) -> [Strip] {
        func rank(_ s: Strip) -> Int {
            if s.active && s.verdict == nil { return 0 }
            if s.awaitsHold { return 1 }
            switch s.verdict {
            case .changes?: return 2
            case .approve?: return 3
            case nil where running: return 4
            case .skipped?, nil: return 5
            }
        }
        return all.enumerated()
            .sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra != rb ? ra < rb : a.offset < b.offset
            }
            .map(\.element)
    }

    /// The first `maxCards` of an ordered list, and how many sit behind the "+N more" strip. A re-rank can push the
    /// open card past the cap: it then takes the last slot, and the card it displaces counts in `more`.
    static func cap(_ list: [Strip], open: String? = nil) -> (cards: [Strip], more: Int) {
        var cards = Array(list.prefix(maxCards))
        if let open, let i = list.firstIndex(where: { $0.id == open }), i >= maxCards {
            cards[maxCards - 1] = list[i]
        }
        return (cards, max(0, list.count - maxCards))
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    /// True only for snapshot rendering: ImageRenderer draws AppKit-backed controls blank.
    var offscreen: Bool
    @StateObject private var local: PopoverModel
    @AppStorage("signalColour") private var signalKey = "amber"
    @Environment(\.colorScheme) private var scheme
    /// Keeps keyboard focus on the popover, so its keys work as soon as it opens.
    @FocusState private var rootFocused: Bool

    private var p: Palette { Palette(scheme) }

    /// `startOpen` is the card to show open at first draw: snapshot rendering only.
    init(store: Store, offscreen: Bool = false, startOpen: String? = nil) {
        self.store = store
        self.offscreen = offscreen
        _local = StateObject(wrappedValue: PopoverModel(openID: startOpen))
    }

    var body: some View {
        let all = stackStrips
        let shown = capped(all)
        let copy = headerCopy
        let ids = ordered(all).map(\.id)
        VStack(alignment: .leading, spacing: 0) {
            stack(all: all, list: shown.cards, more: shown.more, copy: copy)
            digestLine
            updateLine
            ApproachPopoverBlock(store: store, offscreen: offscreen)
            footer
        }
        .frame(width: StackGeometry.width)
        // No square fill at the window's edge: the system's dark frame and rounded corners show through.
        .background {
            // Snapshots have no window to configure; ImageRenderer draws the representable as a prohibition sign.
            if !offscreen { WindowConfigurator { $0.appearance = NSAppearance(named: .darkAqua) } }
        }
        .background(Gotham.void.opacity(offscreen ? 1 : 0.92).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .focusable()
        .focusEffectDisabled()
        .focused($rootFocused)
        .onKeyPress(phases: .down) { handleKey($0) }
        .onAppear {
            guard !offscreen else { return }
            store.popoverOpened()
            local.loginOn = store.loginItemOn
            rootFocused = true
        }
        .onDisappear {
            guard !offscreen else { return }
            local.highlight = nil
            local.openID = nil
            store.popoverClosed()
        }
        // The open card's strip left the list (filtered out or removed): close it rather than leave a blank hole.
        .onChange(of: ids) { _, now in
            if let id = local.openID, !now.contains(id) { local.openID = nil }
        }
    }

    /// The strips in stack order.
    private func ordered(_ all: [Strip]) -> [Strip] {
        StackGeometry.ordered(all, running: store.snap.running)
    }

    /// The cards on the stack: the ordered strips, capped, with the open card kept on. `more` counts the rest.
    private func capped(_ all: [Strip]) -> (cards: [Strip], more: Int) {
        StackGeometry.cap(ordered(all), open: local.openID)
    }

    // MARK: Keys

    /// ↑ ↓ (and Home, End, Page Up, Page Down) move the highlight; Return opens or closes the highlighted card. Esc
    /// closes the open card, then the popover. ⌘R runs a sweep, ⌘. stops one, ⌘O opens the window, ⌘, opens Settings.
    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        guard !TextFocus.isEditing || press.modifiers.contains(.command) else { return .ignored }
        let mods = ShortcutModifiers(press.modifiers)
        let list = capped(stackStrips).cards
        if press.key == .escape, mods.isEmpty {
            if local.openID != nil {
                local.openID = nil
                return .handled
            }
            // Through the status item, as ⌥⌘G does, so the menu bar knows the popover is closed.
            PopoverToggle.toggle()
            return .handled
        }
        if press.key == .return, mods.isEmpty {
            guard let id = local.highlight, list.contains(where: { $0.id == id }) else { return .ignored }
            local.openID = local.openID == id ? nil : id
            return .handled
        }
        if mods == [.command] {
            switch press.characters {
            case "r":
                if !store.snap.running, store.snap.jobInstalled { Confirm.run(store) }
            case ".":
                if store.snap.running { store.stopRun() }
            case "o":
                WindowRouter.shared.open(nil)
            case ",":
                WindowRouter.shared.open(.settings)
            default:
                return .ignored
            }
            return .handled
        }
        if let key = ListKey(press.key), let move = ListNav.move(key, mods) {
            let current = list.firstIndex { $0.id == local.highlight }
            if let i = ListNav.move(move, from: current, count: list.count) { local.highlight = list[i].id }
            return .handled
        }
        return .ignored
    }

    /// What the stack shows: held drafts, PRs in flight, and the newest run's too-large PRs. Other finished reviews are in the digest line.
    private var stackStrips: [Strip] {
        store.strips.filter { $0.draft || ($0.active && $0.verdict == nil) || ($0.offersReview && $0.carriedFrom == nil) }
    }

    /// The newest run's digest, from its own rows: carried rows are left out, so the counts match what the run did.
    private var newestDigest: RunDigest? {
        store.snap.run.map { RunDigest(run: $0, running: store.snap.running) }
    }

    /// The header count for a verdict in the newest run: approved, changes, or skipped.
    private func newestCount(_ verdict: Verdict) -> Int {
        guard let digest = newestDigest else { return 0 }
        if verdict == .skipped { return digest.skipped.values.reduce(0) { $0 + $1.count } }
        return digest.reviewed.filter { $0.pr.verdict == verdict }.count
    }

    /// The newest run in one line: its title, the digest sentence (two lines at most), and Open, which shows Now.
    @ViewBuilder
    private var digestLine: some View {
        if let digest = newestDigest {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(digest.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.ink)
                        .lineLimit(1)
                    Text([digest.lead, digest.rest].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.system(size: 12))
                        .foregroundStyle(p.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                openNowLink
            }
            .padding(.horizontal, StackGeometry.inset + 10)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private var openNowLink: some View {
        if offscreen {
            Text("Open").font(.system(size: 12, weight: .medium)).foregroundStyle(p.ink)
        } else {
            Button("Open") { WindowRouter.shared.open(.now) }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.ink)
        }
    }

    // MARK: Header

    /// The header copy for states the stack cannot show (failure, pause, setup, a sweep starting). Nil for the
    /// quiet states, which the stack and its empty state already say.
    private var headerCopy: HeaderCopy? {
        let now = Date()
        let kind = Presentation.headerKind(store.snap, now: now)
        switch kind {
        case .idle where store.needsCount > 0:
            return HeaderCopy.make(kind, now: now, drafts: store.needsCount)
        case .idle, .emptyRun: return nil
        default: return HeaderCopy.make(kind, now: now, drafts: store.needsCount)
        }
    }

    private func header(all: [Strip], copy: HeaderCopy?, head: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                ForEach([Verdict.approve, .changes, .skipped], id: \.self) { verdict in
                    pip(verdict, count: newestCount(verdict))
                }
                runButton
                windowButton
            }
            .padding(.leading, 10)
            .padding(.trailing, 14)
            .frame(height: 66)
            if let copy {
                captionLine(copy)
                    .frame(height: 22)
                    .padding(.horizontal, StackGeometry.inset + 10)
            }
        }
        .frame(width: StackGeometry.width, height: head, alignment: .topLeading)
        .zIndex(200)
    }

    /// One verdict count of the newest run: a thin numeral over its cap label. Plain counts, not controls.
    private func pip(_ verdict: Verdict, count: Int) -> some View {
        let label = verdict.word
        return VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: "\(count)")
                .font(Gotham.numeral(26))
                .monospacedDigit()
                .foregroundStyle(pipColour(verdict))
            Text(label).cap().lineLimit(1).fixedSize()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(count) \(label)")
    }

    private func pipColour(_ verdict: Verdict) -> Color {
        switch verdict {
        case .approve: return Gotham.approve
        case .changes: return Gotham.signal(signalKey)
        case .skipped: return Gotham.skipped
        }
    }

    private var runButton: some View {
        let snap = store.snap
        let firstRun = snap.repoCount == 0 && !snap.running && !snap.dryRunning
        let enabled = snap.running || snap.dryRunning || snap.paused || firstRun || snap.jobInstalled
        return RunButton(running: snap.running, enabled: enabled,
                         tap: { runTap(firstRun: firstRun) },
                         stop: { store.stopRun() })
    }

    /// Opens the main window, the same as ⌘O.
    private var windowButton: some View {
        Image(systemName: "macwindow")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Gotham.fg)
            .frame(width: 34, height: 34)
            .background(Circle().fill(Gotham.row))
            .contentShape(Circle())
            .onTapGesture { WindowRouter.shared.open(nil) }
            .help("Open Glidepath (⌘O)")
            .accessibilityLabel("Open Glidepath window")
            .accessibilityAddTraits(.isButton)
    }

    /// Run now; the button does the one thing its state offers when a sweep is not running.
    private func runTap(firstRun: Bool) {
        if store.snap.dryRunning { WindowRouter.shared.open(nil) }
        else if store.snap.paused { store.togglePause() }
        else if firstRun { WindowRouter.shared.openOnboarding() }
        else { Confirm.run(store) }
    }

    private func captionLine(_ copy: HeaderCopy) -> some View {
        HStack(spacing: 8) {
            Text([copy.headline, copy.line2].compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tone(copy.headlineTone))
                .lineLimit(1)
            Spacer(minLength: 0)
            if copy.openLog { openLogLink }
        }
    }

    @ViewBuilder
    private var openLogLink: some View {
        if offscreen {
            Text("Open log").font(.system(size: 12, weight: .medium)).foregroundStyle(p.error)
        } else {
            Button("Open log") { store.openLog() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.error)
        }
    }

    private func tone(_ t: HeaderCopy.Tone) -> Color {
        switch t {
        case .ink: return p.ink
        case .secondary: return p.secondary
        case .tertiary: return p.tertiary
        case .changes: return p.changesText
        case .error: return p.error
        }
    }

    // MARK: Stack

    @ViewBuilder
    private func stack(all: [Strip], list: [Strip], more: Int, copy: HeaderCopy?) -> some View {
        // Closed rows: the cards, then the "+N more" strip when cards are left over.
        let rows = list.count + (more > 0 ? 1 : 0)
        let head = StackGeometry.head(caption: copy != nil)
        let step = StackGeometry.step(rows)
        let hi = list.firstIndex { $0.id == local.highlight } ?? -1
        // Open: the cards that peek below the open card, in list order. The rest are not drawn.
        let pile = local.openID == nil ? [] : Array(list.filter { $0.id != local.openID }.prefix(StackGeometry.maxPiled))
        let drawn = Array(list.enumerated()).filter { item in
            local.openID == nil || item.element.id == local.openID || pile.contains { $0.id == item.element.id }
        }
        // One animation for every layout change: open, highlight, and the number of cards.
        let layout = "\(local.openID ?? "")|\(hi)|\(rows)|\(local.openHeight)"
        ZStack(alignment: .topLeading) {
            if rows == 0 {
                emptyState.offset(y: head)
            }
            ForEach(drawn, id: \.element.id) { i, strip in
                let place = placement(i, strip, hi: hi, head: head, step: step, pile: pile)
                StackCard(strip: strip, running: store.snap.running, open: local.openID == strip.id,
                          piled: local.openID != nil && local.openID != strip.id,
                          front: strip.id == pile.last?.id, store: store, model: local)
                    .scaleEffect(place.scale, anchor: .top)
                    .offset(x: StackGeometry.inset, y: place.y)
                    .zIndex(place.z)
                    .transition(.opacity)
            }
            if more > 0, local.openID == nil {
                StackMoreStrip(count: more)
                    .offset(x: StackGeometry.inset, y: head + CGFloat(list.count) * step + (hi >= 0 ? 8 : 0))
                    .zIndex(Double(list.count))
                    .transition(.opacity)
            }
            header(all: all, copy: copy, head: head)
        }
        .frame(width: StackGeometry.width,
               height: StackGeometry.height(rows, head: head, openHeight: local.openID == nil ? nil : local.openHeight,
                                            piled: pile.count),
               alignment: .topLeading)
        .onPreferenceChange(OpenCardHeightKey.self) { if $0 > 0 { local.openHeight = max(StackGeometry.open, $0) } }
        .animation(Motion.stack, value: layout)
    }

    /// Where a card sits, how large, and in which order. Closed: in list order, the highlighted card lifts 3 pt and
    /// the cards below it step down 8 pt. Open: the open card sits at the top, the pile below it in 7 pt steps.
    private func placement(_ i: Int, _ strip: Strip, hi: Int, head: CGFloat, step: CGFloat,
                           pile: [Strip]) -> (y: CGFloat, scale: CGFloat, z: Double) {
        if local.openID != nil {
            if strip.id == local.openID { return (head, 1, 100) }
            let j = pile.firstIndex { $0.id == strip.id } ?? 0
            let k = CGFloat(j)
            return (head + local.openHeight + 14 + k * 7, 0.94 - k * 0.01, Double(10 + j))
        }
        let lift: CGFloat = i == hi ? -3 : (hi >= 0 && i > hi ? 8 : 0)
        return (head + CGFloat(i) * step + lift, 1, Double(i))
    }

    /// Glider and "Nothing needs you", centred in the space the cards would take.
    private var emptyState: some View {
        VStack(spacing: 12) {
            GliderShape()
                .fill(Gotham.mute)
                .frame(width: 40, height: 40)
                .opacity(0.6)
            Text("Nothing needs you")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Gotham.mute)
        }
        .frame(width: StackGeometry.width, height: StackGeometry.emptyHeight)
    }

    // MARK: Update

    /// One line above the footer: an update on offer, its progress or failure, or the result of "Check for updates…".
    @ViewBuilder
    private var updateLine: some View {
        if store.snap.updatePhase == .updating, let update = store.availableUpdate {
            updateRow {
                HStack(spacing: 6) {
                    if offscreen {
                        // ImageRenderer draws ProgressView as a prohibition sign; a symbol stands in for it.
                        Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 11))
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text("Updating to \(update.latest)…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.secondary)
                }
            }
        } else if store.snap.updatePhase == .failed {
            updateRow {
                HStack(spacing: 0) {
                    Text("Update failed · ")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.error)
                    openLogLink
                }
            }
        } else if let note = store.snap.updateNote {
            updateRow {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            }
        } else if store.snap.updateChecking {
            updateRow {
                Text("Checking for updates…")
                    .font(.system(size: 12))
                    .foregroundStyle(p.secondary)
            }
        } else if let update = store.availableUpdate {
            updateRow {
                HStack(spacing: 0) {
                    Text("Glidepath \(update.latest) is available")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.ink)
                    Spacer(minLength: 8)
                    linkButton("What's new") {
                        if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
                    }
                    linkButton("Update") { confirmAndUpdate(update) }
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func updateRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.inset)
            .padding(.top, 12)
    }

    @ViewBuilder
    private func linkButton(_ label: String, _ action: @escaping () -> Void) -> some View {
        if offscreen {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(p.doingText)
        } else {
            Button(label, action: action)
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(p.doingText)
        }
    }

    // MARK: Footer

    /// The "more" menu: everything the header does not carry. Its row ends where the menu ends.
    private var footer: some View {
        HStack(spacing: 8) {
            Spacer(minLength: 0)
            if offscreen {
                // ImageRenderer draws AppKit menus as a prohibition sign; the symbol stands in for the menu.
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Gotham.fg)
            } else {
                Menu {
                    Button("Open Glidepath") { WindowRouter.shared.open(nil) }
                    Divider()
                    if let update = store.availableUpdate {
                        Button("Update to \(update.latest)…") { confirmAndUpdate(update) }
                            .disabled(store.snap.updatePhase == .updating)
                    } else {
                        Button("Glidepath \(Version.current)") {}
                            .disabled(true)
                    }
                    Divider()
                    Button(store.snap.paused ? "Resume" : "Pause") { store.togglePause() }
                    Button("Open log") { store.openLog() }
                    Button("History") { WindowRouter.shared.open(.reviews) }
                    Button("Check for updates…") { store.checkForUpdates(manual: true) }
                        .disabled(store.snap.updateChecking)
                    if let tokens = store.snap.run?.tokens, tokens > 0 {
                        Divider()
                        Button("Last run: \(compactTokens(tokens)) tokens") {}
                            .disabled(true)
                    }
                    Divider()
                    Toggle("Open at login", isOn: Binding(
                        get: { local.loginOn },
                        set: { on in
                            store.setLoginItem(on)
                            local.loginOn = store.loginItemOn
                        }
                    ))
                    Divider()
                    Button("Quit Glidepath") { NSApp.terminate(nil) }
                        .keyboardShortcut("q")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(Gotham.fg)
                        .accessibilityLabel("More")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, Metrics.inset)
        .frame(height: Metrics.footerRow)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    /// Updating is public-facing and restarts the app, so a Homebrew install asks first; anything else opens the
    /// release page.
    private func confirmAndUpdate(_ update: UpdateCache) {
        guard store.updatesWithBrew else {
            if let url = URL(string: update.url) { NSWorkspace.shared.open(url) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update Glidepath to \(update.latest)?"
        alert.informativeText = "Homebrew rebuilds it from source, which takes about a minute. The app restarts when it's done."
            + (store.snap.running ? " A sweep is running, so the update starts when it ends." : "")
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.startUpdate()
    }
}

/// The round run button. Tap runs a sweep. While one runs it wears the tracer, and a hold of 0.9 s stops it, the fill
/// rising under the finger as the hold builds.
struct RunButton: View {
    let running: Bool
    let enabled: Bool
    let tap: () -> Void
    let stop: () -> Void

    @StateObject private var fill = FillModel()

    var body: some View {
        ZStack {
            Circle().fill(Gotham.row)
            Rectangle()
                .fill(Gotham.fg.opacity(0.22))
                .frame(height: 34 * fill.level)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .clipShape(Circle())
            Group {
                if running {
                    RoundedRectangle(cornerRadius: 2, style: .continuous).frame(width: 9, height: 9)
                } else {
                    PlayShape().frame(width: 11, height: 12).offset(x: 1)
                }
            }
            .foregroundStyle(Gotham.fg)
        }
        .frame(width: 34, height: 34)
        .overlay { if running { Tracer(shape: Circle(), lineWidth: 1) } }
        .contentShape(Circle())
        .opacity(enabled || running ? 1 : 0.4)
        .onTapGesture { if !running && enabled { tap() } }
        .onLongPressGesture(minimumDuration: 0.9, maximumDistance: 30, perform: {
            guard running else { return }
            fill.level = 0
            stop()
        }, onPressingChanged: { down in
            guard running else { return }
            withAnimation(down ? .linear(duration: 0.9) : .easeOut(duration: 0.2)) { fill.level = down ? 1 : 0 }
        })
        .accessibilityLabel(running ? "Hold to stop the sweep" : "Run now")
        .accessibilityAddTraits(.isButton)
    }
}

/// The play triangle of the run button.
struct PlayShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// The glider glyph of the empty state: the prototype's 24-unit path, scaled to the frame.
struct GliderShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var p = Path()
        p.move(to: pt(2.5, 11.2))
        p.addLine(to: pt(21, 3.6))
        p.addCurve(to: pt(21.8, 4.4), control1: pt(21.5, 3.4), control2: pt(22, 3.9))
        p.addLine(to: pt(14.2, 22.9))
        p.addCurve(to: pt(13.1, 22.9), control1: pt(14.0, 23.4), control2: pt(13.3, 23.4))
        p.addLine(to: pt(10.5, 16.3))
        p.addCurve(to: pt(9.9, 15.7), control1: pt(10.4, 16.0), control2: pt(10.2, 15.8))
        p.addLine(to: pt(3.3, 13))
        p.addCurve(to: pt(3.2, 11.8), control1: pt(2.7, 12.8), control2: pt(2.7, 12.0))
        p.closeSubpath()
        return p
    }
}

/// The skipped-for-size wording of a row, used by the tests.
enum PRRow {
    static func skippedText(_ reason: String?) -> String {
        guard let reason, !reason.isEmpty else { return "Skipped" }
        return reason.prefix(1).uppercased() + reason.dropFirst() + ", skipped"
    }
}
