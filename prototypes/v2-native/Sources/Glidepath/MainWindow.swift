import SwiftUI

struct MainWindow: View {
    @Environment(Store.self) private var store
    @Environment(\.undoManager) private var undo

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            List(selection: Binding(get: { store.page }, set: { if let p = $0 { go(p) } })) {
                ForEach(Page.allCases) { page in
                    Label {
                        Text(page.rawValue)
                    } icon: {
                        Image(systemName: page.symbol).foregroundStyle(Color.graphite)
                    }
                        .badge(page == .inbox ? store.needsCount : 0)
                        .tag(page)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            page
                .inspector(isPresented: $store.showInspector) {
                    Inspector()
                        .inspectorColumnWidth(min: 360, ideal: 420, max: 560)
                        .opacity(store.morphFrom == nil ? 1 : 0)
                        .background(Anchor { store.inspectorView = $0 })
                }
                .overlay(alignment: .bottom) {
                    if let b = store.banner {
                        BannerView(banner: b) { store.undoBanner(undo) }
                    }
                }
        }
        .overlay { InspectorMorph() }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)   // one sheet of glass, no title band
        .sheet(isPresented: $store.showOnboarding) { Onboarding() }
        .sheet(isPresented: $store.showShortcuts) { ShortcutsSheet() }
        .sheet(isPresented: $store.showLog) { LogSheet() }
        .frame(minWidth: 860, minHeight: 520)
    }

    private func go(_ p: Page) {
        store.page = p
        store.showInspector = false
        store.inspected = nil
    }

    @ViewBuilder private var page: some View {
        switch store.page {
        case .inbox: InboxPage()
        case .prs: PRsPage()
        case .activity: ActivityPage()
        case .repos: ReposPage()
        }
    }
}

/// Title, status sentence as the subtitle, one primary button. Same on every page.
struct PageChrome: ViewModifier {
    @Environment(Store.self) private var store
    let title: String

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            GlideLine().padding(.horizontal, 22)
            // Content starts below the line, so nothing scrolls under the toolbar: no edge effect band.
            content.scrollEdgeEffectHidden(true, for: .top)
        }
            .navigationTitle(title)
            .navigationSubtitle(store.windowStatus.text)
            .toolbar {
                // Problem: the Fix button lives in the line's gap instead.
                if store.lineMode != .problem {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.primary()
                    } label: {
                        Label(store.windowStatus.button, systemImage: store.windowStatus.symbol)
                            .labelStyle(.titleAndIcon)
                    }
                    .help(store.windowStatus.button)
                }
                }
            }
    }
}

extension View {
    func pageChrome(_ title: String) -> some View { modifier(PageChrome(title: title)) }
}

// MARK: - Inbox

struct InboxPage: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    @State private var ghost: Ghost?
    @State private var countFrame: CGRect = .zero

    /// The row that is gliding down into the Done today count.
    struct Ghost: Equatable { var pr: PR; var from: CGRect; var to: CGPoint; var landed = false; var faded = false }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if store.needsYou.isEmpty {
                    touchdown
                } else {
                    GlassEffectContainer(spacing: 14) {
                        VStack(spacing: 10) {
                            ForEach(store.needsYou) { pr in
                                NeedsPane(pr: pr, selected: store.inspected == .pr(pr.id), ns: glass)
                                    // A landing row hands over to its ghost at once; anything else fades.
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: -12, y: -6)),
                                                            removal: store.landing == pr.id ? .identity : .opacity))
                            }
                        }
                    }
                }
                if store.checking { working }
                done
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 28)
            .coordinateSpace(.named("inbox"))
            .overlay(alignment: .topLeading) { ghostView }
        }
        .focusable()
        .focusEffectDisabled()
        .keyNav()
        .pageChrome("Inbox")
        .onChange(of: store.landing) { _, id in if let id { land(id) } }
    }

    // When the last item lands: the line settles and this fades in under it.
    private var touchdown: some View {
        VStack(spacing: 6) {
            Text("Nothing needs you").font(.title3.weight(.semibold))
            Text(emptyLine).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
        .padding(.bottom, 40)
        .transition(.opacity.animation(.easeOut(duration: 0.8).delay(reduceMotion ? 0 : 0.7)))
    }

    private var working: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Working now").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 14)
            ForEach(store.working) { w in
                if let pr = store.pr(w.id) {
                    HStack(spacing: 12) {
                        Avatar(login: pr.author)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pr.title).lineLimit(1)
                            Text("\(w.stage)  ·  \(pr.ref)").font(.subheadline).foregroundStyle(.secondary)
                                .contentTransition(.opacity)
                        }
                        Spacer()
                        ProgressView().controlSize(.small)
                    }
                    .padding(.horizontal, 14)
                }
            }
        }
        .transition(.opacity)
    }

    private var done: some View {
        @Bindable var store = store
        let shown = store.doneToday.count - (store.landing != nil ? 1 : 0)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.smooth) { store.showDone.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Done today").font(.headline)
                    // The count sits on its label: the signature glide lands here.
                    Text("\(shown)")
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(shown)))
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .background(.white.opacity(0.1), in: .capsule)
                        .geometryGroup()   // the number and its capsule move as one while rows above glide away
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("inbox")) } action: { countFrame = $0 }
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(store.showDone ? 90 : 0))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            if store.showDone {
                VStack(spacing: 2) {
                    ForEach(store.doneToday) { item in
                        ActivityRow(item: item)
                            .padding(.horizontal, 14).padding(.vertical, 5)
                            .contentShape(.rect)
                            .onTapGesture { if let id = item.pr { store.select(id) } }
                    }
                }
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder private var ghostView: some View {
        if let g = ghost {
            // The pane gives up its words early and keeps travelling as a small bead of glass.
            let size = g.landed ? CGSize(width: 26, height: 10) : g.from.size
            NeedsPaneBody(pr: g.pr)
                .padding(14)
                .frame(width: g.from.width, height: g.from.height)
                .opacity(g.landed ? 0 : 1)
                .frame(width: size.width, height: size.height)
                .background(LightFill(progress: 1).opacity(g.landed ? 0.6 : 1))
                .clipShape(.rect(cornerRadius: g.landed ? 5 : 18))
                .glassEffect(.regular.tint(.black.opacity(0.3)), in: .rect(cornerRadius: g.landed ? 5 : 18))
                .opacity(g.faded ? 0 : 1)
                .position(g.landed ? g.to : CGPoint(x: g.from.midX, y: g.from.midY))
                .allowsHitTesting(false)
        }
    }

    /// Signature: the filled row glides down and to the right, shrinks and settles into the count.
    private func land(_ id: String) {
        guard let pr = store.pr(id) else { store.landing = nil; return }
        let from = store.rowFrames[id] ?? .zero
        if reduceMotion || from == .zero {
            withAnimation(.easeInOut(duration: 0.35)) { store.perform(id); store.landing = nil }
            return
        }
        // The count moves up by one row once this row is gone (or the touchdown block replaces the list).
        let shift = store.needsCount == 1 ? from.height + 10 - 140 : from.height + 10
        let to = CGPoint(x: countFrame.midX, y: countFrame.midY - shift)
        ghost = Ghost(pr: pr, from: from, to: to)
        withAnimation(.glide) { store.perform(id) }
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(.spring(duration: 0.95, bounce: 0)) { ghost?.landed = true }
            withAnimation(.easeIn(duration: 0.25).delay(0.65)) { ghost?.faded = true }
            try? await Task.sleep(for: .seconds(0.85))
            withAnimation(.smooth(duration: 0.5)) { store.landing = nil }
            try? await Task.sleep(for: .seconds(0.4))
            ghost = nil
        }
    }

    private var emptyLine: String {
        if store.problem { return "New checks wait until you sign in to GitHub again." }
        if let p = store.pausedUntil { return "Checks resume \(p)." }
        if store.hold == .reserve { return "Checks resume at 4:10 PM, when your usage window resets." }
        if store.hold == .quiet { return "3 fixes start at 7:00 PM, when quiet hours begin." }
        if store.checking { return "Checking now. Anything that needs you lands here." }
        return "Next check at 5:00 PM."
    }
}

/// A Needs you item: its own pane of interactive glass. Holding its button fills the pane with light.
struct NeedsPane: View {
    @Environment(Store.self) private var store
    let pr: PR
    let selected: Bool
    let ns: Namespace.ID
    @State private var progress: CGFloat = 0

    var body: some View {
        let held = (store.spaceHeld && selected) || store.debugHold == pr.id
        NeedsPaneBody(pr: pr) {
            if let need = pr.need {
                HoldButton(title: need.button, hint: need.hint, hold: need.isHold, external: held, progress: $progress) { store.complete(pr.id) }
            }
            PRMenu(pr: pr)
        }
        .padding(14)
        .background(LightFill(progress: progress))
        .clipShape(.rect(cornerRadius: 18))
        .contentShape(.rect(cornerRadius: 18))
        .glassEffect(.regular.tint(selected ? .white.opacity(0.08) : .black.opacity(0.3)).interactive(), in: .rect(cornerRadius: 18))
        .glassEffectID(pr.id, in: ns)
        .overlay {
            if selected { RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.22), lineWidth: 1) }
        }
        .onTapGesture { store.select(pr.id) }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("inbox")) } action: { store.rowFrames[pr.id] = $0 }
        .background(Anchor { store.rowViews[pr.id] = $0 })
        .contextMenu { PRMenuItems(pr: pr) }
    }
}

struct NeedsPaneBody<Trailing: View>: View {
    let pr: PR
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            Avatar(login: pr.author, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title).font(.body.weight(.medium)).lineLimit(1)
                NeedLine(pr: pr)
                Text(pr.reason).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

extension NeedsPaneBody where Trailing == EmptyView {
    init(pr: PR) { self.pr = pr; self.trailing = EmptyView() }
}

struct PRMenu: View {
    let pr: PR
    var body: some View {
        Menu {
            PRMenuItems(pr: pr)
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("More")
    }
}

struct PRMenuItems: View {
    @Environment(Store.self) private var store
    @Environment(\.undoManager) private var undo
    let pr: PR
    var body: some View {
        Button("Open on GitHub", systemImage: "arrow.up.right.square") {}
        if pr.need == .post { Button("Edit Review…", systemImage: "pencil") {} }
        if pr.state == .skipped { Button("Review Anyway", systemImage: "text.bubble") {} }
        if pr.need != .stuck { Button("Try Again", systemImage: "arrow.clockwise") {} }
        if pr.need != nil {
            Divider()
            Button("Discard", systemImage: "trash") { store.discard(pr.id, undo: undo) }
        }
    }
}

// MARK: - PRs

struct PRsPage: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        List(selection: Binding(get: { store.inspected }, set: { store.inspected = $0; store.showInspector = $0 != nil })) {
            if store.yourTab {
                ForEach(MineGroup.allCases, id: \.self) { g in
                    let rows = store.prs.filter { $0.mine && group(of: $0) == g }
                    if !rows.isEmpty {
                        Section {
                            ListHeader(title: g.title)
                            ForEach(rows) { PRRow(pr: $0).tag(Inspected.pr($0.id)) }
                        }
                    }
                }
            } else {
                ForEach(teamGroups, id: \.0) { title, state in
                    let rows = store.prs.filter { !$0.mine && $0.state == state }
                    if !rows.isEmpty {
                        Section {
                            ListHeader(title: title)
                            ForEach(rows) { PRRow(pr: $0).tag(Inspected.pr($0.id)) }
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .keyNav()
        .pageChrome("PRs")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Show", selection: $store.yourTab) {
                    Text("Team PRs").tag(false)
                    Text("Your PRs").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private let teamGroups: [(String, TeamState)] = [("Ready to post", .ready), ("Reviewed", .reviewed), ("Skipped", .skipped), ("Not checked yet", .unchecked)]
    private func group(of p: PR) -> MineGroup { p.need != nil ? .needsYou : (p.group == .needsYou ? .onIt : p.group) }
}

struct PRRow: View {
    let pr: PR
    var body: some View {
        HStack(spacing: 12) {
            Avatar(login: pr.author)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title).lineLimit(1)
                if pr.mine {
                    NeedLine(pr: pr)
                } else {
                    Text("\(pr.ref)  ·  \(pr.author)").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 16)
            if pr.mine {
                ProgressStrip(steps: pr.steps)
            } else {
                Text(trailing).font(.subheadline).foregroundStyle(pr.need != nil ? Color.amber : .secondary).lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .contextMenu { PRMenuItems(pr: pr) }
    }

    private var trailing: String {
        switch pr.state {
        case .ready: "Ready to post"
        case .reviewed: pr.verdict
        case .skipped: pr.skip.components(separatedBy: ".").first ?? pr.skip
        case .unchecked: "\(pr.lines) lines"
        }
    }
}

/// A group title as an ordinary row: a pinned section header draws a grey band under the glide line on the smoked glass.
struct ListHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.headline).foregroundStyle(.secondary)
            .padding(.top, 10)
            .listRowSeparator(.hidden)
            .selectionDisabled()
    }
}

// MARK: - Activity

struct ActivityPage: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let items = filtered
        Group {
            if items.isEmpty {
                if store.search.isEmpty {
                    ContentUnavailableView("No activity yet", systemImage: "clock",
                                           description: Text("What Glidepath does shows up here, newest first."))
                } else {
                    ContentUnavailableView.search(text: store.search)
                }
            } else {
                List(selection: Binding(get: { store.inspected }, set: { store.inspected = $0; store.showInspector = $0 != nil })) {
                    ForEach([0, -1], id: \.self) { day in
                        let rows = items.filter { $0.day == day }
                        if !rows.isEmpty {
                            Section {
                                ListHeader(title: day == 0 ? "Today" : "Yesterday")
                                ForEach(rows) { item in
                                    ActivityRow(item: item, showFix: true)
                                        .tag(item.pr.map { Inspected.pr($0) })
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
        .scrollContentBackground(.hidden)
            }
        }
        .pageChrome("Activity")
        .searchable(text: $store.search, placement: .toolbar, prompt: "Search activity")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Filter", selection: $store.activityFilter) {
                    ForEach(ActivityFilter.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    private var filtered: [ActivityItem] {
        store.activity.filter { item in
            let kindOK: Bool = switch store.activityFilter {
            case .all: true
            case .reviews: item.kind == .review || item.kind == .skip
            case .yours: item.kind == .mine
            case .problems: item.kind == .problem
            }
            guard kindOK else { return false }
            if store.search.isEmpty { return true }
            let hay = item.text + " " + (item.pr.flatMap { store.pr($0).map { "\($0.ref) \($0.title)" } } ?? "")
            return hay.localizedCaseInsensitiveContains(store.search)
        }
    }
}

struct ActivityRow: View {
    @Environment(Store.self) private var store
    let item: ActivityItem
    var showFix = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.kind.symbol)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                if let id = item.pr, let pr = store.pr(id) {
                    Text(pr.title).lineLimit(1)
                    Text("\(item.text)  ·  \(pr.ref)").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text(item.text).lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            if showFix, let fix = item.fix {
                Button(fix) { fix == "Fix" ? store.primary() : (store.showLog = true) }
                    .controlSize(.small)
            }
            Text(item.time).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Repos

struct ReposPage: View {
    @Environment(Store.self) private var store
    @Environment(\.undoManager) private var undo

    var body: some View {
        @Bindable var store = store
        Group {
            if store.repos.isEmpty {
                ContentUnavailableView {
                    Label("No repos", systemImage: "books.vertical")
                } description: {
                    Text("Add a repo and Glidepath starts checking it at the next check.")
                } actions: {
                    Button("Add Repo…") {}
                }
            } else {
                // A list, not a Table: a Table's column header draws a grey band under the glide line on the smoked glass.
                List(selection: Binding(get: { store.inspected }, set: { store.inspected = $0; store.showInspector = $0 != nil })) {
                    ForEach($store.repos) { $repo in
                        HStack(spacing: 24) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(repo.name).font(.body.weight(.medium)).foregroundStyle(.primary)
                                Text(repo.last).font(.subheadline).lineLimit(1)
                            }
                            Spacer(minLength: 16)
                            Toggle("Review team PRs", isOn: $repo.review).fixedSize()
                            Toggle("Look after my PRs", isOn: $repo.lookAfter).fixedSize()
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .tag(Inspected.repo(repo.name))
                        .contextMenu {
                            Button("Open on GitHub", systemImage: "arrow.up.right.square") {}
                            Divider()
                            Button("Remove Repo", systemImage: "minus.circle") { store.removeRepo(repo.name, undo: undo) }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .pageChrome("Repos")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button("Add Repo", systemImage: "plus") {}.help("Add Repo")
            }
        }
    }
}

// MARK: - Keyboard

struct KeyNav: ViewModifier {
    @Environment(Store.self) private var store
    func body(content: Content) -> some View {
        content
            .onKeyPress("j") { move(1); return .handled }
            .onKeyPress("k") { move(-1); return .handled }
            .onKeyPress(.return) { store.showInspector.toggle(); return .handled }
            .onKeyPress(keys: [.space], phases: [.down, .up]) { press in
                guard case .pr(let id) = store.inspected, store.pr(id)?.need != nil else { return .ignored }
                store.spaceHeld = press.phase == .down
                return .handled
            }
    }

    private func move(_ d: Int) {
        let ids: [String] = switch store.page {
        case .inbox: store.needsYou.map(\.id)
        default: store.prs.filter { $0.mine == store.yourTab }.map(\.id)
        }
        guard !ids.isEmpty else { return }
        var i = -1
        if case .pr(let cur) = store.inspected, let at = ids.firstIndex(of: cur) { i = at }
        let next = ids[max(0, min(ids.count - 1, i + d))]
        store.select(next)
    }
}

extension View { func keyNav() -> some View { modifier(KeyNav()) } }

struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss
    private let rows: [(String, String)] = [
        ("J / K", "Move down / up"), ("Return", "Open the PR"), ("Hold Space", "Post, push, send or merge"),
        ("⌘Z", "Undo"), ("⌘.", "Stop"), ("⌘R", "Check now"), ("⌘1 – ⌘4", "Go to a page"), ("⌘,", "Settings"),
    ]
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Keyboard Shortcuts") {
                    ForEach(rows, id: \.0) { k, v in
                        LabeledContent(v) { Text(k).font(.body.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }
        .frame(width: 380, height: 420)
    }
}

struct LogSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Check at 9:00 AM, SagerDrone/Sager") {
                    LabeledContent("Fetched the open PRs") { Text("9:00 AM") }
                    LabeledContent("GitHub rate limit reached; waiting 20 minutes") { Text("9:00 AM") }
                    LabeledContent("Tried again; it worked") { Text("9:20 AM") }
                }
            }
            .formStyle(.grouped)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }.padding()
        }
        .frame(width: 460, height: 280)
    }
}

/// The selected row's glass grows into the inspector. The inspector is its own column (its own hosting view),
/// so a true glassEffectID morph can't cross into it; this window-level pane of glass travels the gap instead.
struct InspectorMorph: View {
    @Environment(Store.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pr: PR?
    @State private var from: CGRect = .zero
    @State private var rect: CGRect = .zero
    @State private var arrived = false
    @State private var me: NSView?
    @State private var size: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topLeading) {
            // A 1 pt anchor at the overlay's corner: a full-size AppKit view here would give the toolbar a backing.
            Anchor { me = $0 }.frame(width: 1, height: 1)
            if let pr {
                NeedsPaneBody(pr: pr)
                    .padding(14)
                    .frame(width: from.width, height: from.height)
                    .opacity(arrived ? 0 : 1)
                    .frame(width: rect.width, height: rect.height, alignment: .topLeading)
                    .clipShape(.rect(cornerRadius: 18))
                    .glassEffect(.regular.tint(.white.opacity(0.06)), in: .rect(cornerRadius: 18))
                    .offset(x: rect.minX, y: rect.minY)
                    .transition(.opacity.animation(.easeOut(duration: 0.25)))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .allowsHitTesting(false)
        .onChange(of: store.morphFrom) { _, id in
            guard let id, !reduceMotion, let row = store.rowViews[id], let me else { store.morphFrom = nil; return }
            pr = store.pr(id); from = Anchor.rect(of: row, in: me); rect = from; arrived = false
            Task {
                try? await Task.sleep(for: .milliseconds(30))   // let the inspector column take its width
                // Lands where the inspector's first card will sit once the column has slid open.
                let w = store.inspectorView?.bounds.width ?? 420
                let col = CGRect(x: size.width - w, y: 0, width: w, height: 400)
                withAnimation(.spring(duration: 0.55, bounce: 0)) {
                    rect = CGRect(x: col.minX + 10, y: col.minY + 10, width: col.width - 20, height: 214); arrived = true
                }
                try? await Task.sleep(for: .seconds(0.5))
                withAnimation(.easeOut(duration: 0.3)) { store.morphFrom = nil; pr = nil }
            }
        }
    }
}

/// Hands over the AppKit view behind a SwiftUI view, so frames can be compared across split view columns,
/// which are separate hosting views where SwiftUI coordinate spaces don't reach.
struct Anchor: NSViewRepresentable {
    let found: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async { found(v) }
        return v
    }
    func updateNSView(_ v: NSView, context: Context) {}

    /// `view`'s bounds in `space`'s top-left coordinates.
    static func rect(of view: NSView, in space: NSView) -> CGRect {
        let r = space.convert(view.bounds, from: view)
        return space.isFlipped ? r : CGRect(x: r.minX, y: space.bounds.height - r.maxY, width: r.width, height: r.height)
    }
}
