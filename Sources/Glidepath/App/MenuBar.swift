import AppKit
import SwiftUI
import Combine

/// The menu bar item: the glide line as a template image with the Needs-you count beside it, the popover on a left
/// click and a native menu on a right click. AppKit-hosted on purpose: SwiftUI's MenuBarExtra redrew its label on every
/// animation frame anywhere in the app, which the living line turned into a busy loop. Here the image changes only when
/// the state or the count does, plus a slow tick for the checking dot, so the app idles at ~0% CPU.
@MainActor
final class MenuBar: NSObject, NSPopoverDelegate {
    static private(set) var shared: MenuBar?

    /// One pass of the checking dot along the line, and how often it steps.
    static let pass: TimeInterval = 3
    static let tick: TimeInterval = pass / Double(GlideGlyph.frames)

    private let store: Store
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private var sink: AnyCancellable?
    private var ticker: Timer?
    /// When the popover last closed. A click on the icon closes a transient popover on mouse-down, before the click
    /// itself arrives on mouse-up; this keeps that click from opening it again.
    private var closedAt = Date.distantPast
    static let reopenDelay: TimeInterval = 0.3

    static func install() {
        shared = MenuBar(store: .shared)
    }

    private init(store: Store) {
        self.store = store
        super.init()
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        if let button = item.button {
            button.target = self
            button.action = #selector(click)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }
        sink = store.$status.combineLatest(store.$needsYou.map(\.count).removeDuplicates())
            .sink { [weak self] state, count in self?.render(state, count: count) }
    }

    // MARK: Icon

    private func render(_ state: GlideState, count: Int) {
        guard let button = item.button else { return }
        let title = count > 0 && !Self.hidesCount(state) ? "\(count)" : ""
        if button.title != title { button.title = title }
        button.setAccessibilityLabel(Copy.status(state))
        if case .checking = state, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            if ticker == nil {
                let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.step() }
                }
                timer.tolerance = Self.tick / 4
                RunLoop.main.add(timer, forMode: .common)
                ticker = timer
            }
            step()
        } else {
            ticker?.invalidate()
            ticker = nil
            show(GlideGlyph.image(for: state, phase: 0.5))
        }
    }

    /// Paused and problem shapes say it all; a count beside them would read as more to do.
    static func hidesCount(_ state: GlideState) -> Bool {
        switch state {
        case .problem, .paused: return true
        default: return false
        }
    }

    private func step() {
        let phase = Date().timeIntervalSinceReferenceDate / Self.pass
        show(GlideGlyph.image(for: store.status, phase: phase))
    }

    /// Glyphs are cached, so an unchanged frame is the same object and the button is left alone.
    private func show(_ image: NSImage) {
        if item.button?.image !== image { item.button?.image = image }
    }

    // MARK: Clicks

    @objc private func click() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            close()
            item.menu = menu(full: true)
            item.button?.performClick(nil)
            item.menu = nil
        } else if popover.isShown || !Self.justClosed(closedAt, now: Date()) {
            toggle()
        }
    }

    /// True for a click that arrives within `reopenDelay` of the popover closing: the click that closed it.
    static func justClosed(_ closedAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(closedAt) < reopenDelay
    }

    func toggle() {
        if popover.isShown { close(); return }
        guard let button = item.button else { return }
        // Built for each opening and dropped on close, so the popover's animations cannot tick while it is closed.
        let host = NSHostingController(rootView: MenuPopover(store: store, close: { MenuBar.shared?.close() })
            .tint(.graphite))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func close() {
        if popover.isShown { popover.performClose(nil) }
    }

    func popoverWillShow(_ notification: Notification) { store.popoverOpened() }

    /// Stamped as the close starts (on the mouse-down), before the click's mouse-up can reach `click`.
    func popoverWillClose(_ notification: Notification) { closedAt = Date() }

    /// Closing is a look: the next "Since you last looked" starts here.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
        store.popoverClosed()
    }

    // MARK: Menu

    /// The right-click menu, and without Settings and Quit, the Dock menu.
    func menu(full: Bool) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let snap = store.snap
        let check = ActionItem(Copy.checkNow) { [store] in MenuActions.perform(.checkNow, store: store) }
        check.isEnabled = MenuActions.canCheck(snap)
        menu.addItem(check)
        let pause = NSMenuItem(title: Copy.pause, action: nil, keyEquivalent: "")
        let choices = NSMenu()
        if snap.paused {
            choices.addItem(ActionItem(Copy.resume) { [store] in MenuActions.perform(.resume, store: store) })
            choices.addItem(.separator())
        }
        for choice in MenuActions.pauseChoices() {
            choices.addItem(ActionItem(choice.title) { [store] in MenuActions.perform(.pause(until: choice.until), store: store) })
        }
        pause.submenu = choices
        menu.addItem(pause)
        menu.addItem(ActionItem(Copy.openGlidepath) { [store] in MenuActions.perform(.openWindow, store: store) })
        guard full else { return menu }
        menu.addItem(.separator())
        menu.addItem(ActionItem(Copy.settings, key: ",") { [store] in MenuActions.perform(.settings, store: store) })
        menu.addItem(.separator())
        menu.addItem(ActionItem(Copy.quit, key: "q") { NSApp.terminate(nil) })
        return menu
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private var handler: () -> Void = {}

    convenience init(_ title: String, key: String = "", _ handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        self.handler = handler
        target = self
    }

    @objc private func fire() { handler() }
}
