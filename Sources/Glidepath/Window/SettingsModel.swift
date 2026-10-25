import SwiftUI
import AppKit

/// The Settings section's state. Every config change goes through `commit`: one edit applied to config.toml as it is on
/// disk, saved, then the store reloads. Look keys (glyph, badge, signal colour, glass, motion) live in UserDefaults.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var rowErrors: [String: String] = [:]
    @Published var query = ""
    @Published private(set) var loginOn = false
    @Published private(set) var tools: [Checks.Item] = []
    @Published private(set) var checking = false
    @Published private(set) var uninstalling = false
    @Published private(set) var uninstallNote: String?
    @Published private(set) var toastText: String?
    @Published private(set) var usedTokens = 0
    @Published private(set) var recording = false
    @Published var drawerOpen = false
    @Published private(set) var tomlLines: [String] = []
    @Published private(set) var tomlChanged: Set<Int> = []
    /// The chip last clicked, lit until another is clicked.
    @Published var chip = "review"
    /// Bumped by a reset so its hold button starts again.
    @Published private(set) var resetCount = 0
    let saved = SavedFlash()

    private var keyMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    /// The custom shortcut text last switched off, so turning the shortcut back on restores it.
    private var rememberedShortcut: String?

    /// The UserDefaults keys the look rows own. Reset clears them with the config keys.
    static let lookKeys = ["glyphStyle", "glyphBadge", "signalColour", "glassBlur", "motion"]

    // MARK: Search

    /// True when a row's label or caption matches the search, or there is no search.
    func matches(_ row: SettingsCopy.Row) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return q.isEmpty || row.text.lowercased().contains(q)
    }

    /// True when a group has at least one row that matches.
    func matches(_ block: SettingsCopy.Block) -> Bool {
        block.rows.contains { matches($0) }
    }

    // MARK: Loading

    /// Reads the live login item, this month's token use, and the tool checks.
    func refresh(_ store: Store) {
        loginOn = store.loginItemOn
        refreshUsed(store)
        if store.isFixture {
            tools = store.snap.tools ?? []
            return
        }
        runChecks(store.paths)
    }

    /// Tokens used by the runs that started this calendar month. The budget ring reads it.
    func refreshUsed(_ store: Store) {
        usedTokens = TokenBudget.used(store.allRuns(), now: Date())
    }

    // MARK: Commit

    /// Applies one change to config.toml as it is on disk now, so a hand edit since the window loaded the file is kept.
    /// On success the store reloads and the Saved stamp shows (and the toast, when given). `onSaved` runs after the save
    /// and returns a message when the change could not take effect outside config.toml. On failure the message goes to
    /// `row` and nothing is written.
    func commit(_ row: String, store: Store, toast message: String? = nil, onSaved: (() -> String?)? = nil,
                _ change: @escaping @Sendable (Config) throws -> Config) {
        let paths = store.paths
        Task {
            do {
                try await ConfigWriter.shared.apply(paths: paths, change: change) { try ConfigEditor.save($0, paths: paths) }
                rowErrors[row] = onSaved?()
                saved.flash()
                if let message { toast(message) }
            } catch let error as ConfigError {
                rowErrors[row] = error.message
            } catch {
                rowErrors[row] = "Could not save: \(error.localizedDescription)"
            }
            store.reload()
        }
    }

    /// Runs one per-repo edit on every repo in the config, in one save. An error from any repo stops the whole save.
    func eachRepo(_ row: String, store: Store, _ edit: @escaping @Sendable (Config, String) throws -> Config) {
        commit(row, store: store) { config in
            var out = config
            for slug in config.repos.map(\.slug) { out = try edit(out, slug) }
            return out
        }
    }

    /// Adds a flagged path to every repo that does not have it yet.
    func addFlag(_ path: String, store: Store) {
        commit("flags", store: store) { config in
            var out = config
            for repo in config.repos where !repo.flagPaths.contains(path) {
                out = try ConfigEditor.addFlaggedPath(out, slug: repo.slug, path: path)
            }
            return out
        }
    }

    /// Removes a flagged path from every repo that has it.
    func removeFlag(_ path: String, store: Store) {
        commit("flags", store: store) { config in
            var out = config
            for repo in config.repos where repo.flagPaths.contains(path) {
                out = try ConfigEditor.removeFlaggedPath(out, slug: repo.slug, path: path)
            }
            return out
        }
    }

    /// Restores the settings rows to their defaults and clears the look keys. Repos and per-repo values stay.
    func resetSettings(_ store: Store) {
        for key in Self.lookKeys { UserDefaults.standard.removeObject(forKey: key) }
        resetCount += 1
        commit("reset", store: store, toast: "Settings reset") { config in
            var c = ConfigEditor.setReviewDrafts(config, false)
            c = ConfigEditor.setIncludeBots(c, false)
            c = ConfigEditor.setModel(c, .opus)
            c = ConfigEditor.setStrictness(c, .balanced)
            c = ConfigEditor.setNotifyChangesOnly(c, false)
            c = ConfigEditor.setNotifySound(c, .glass)
            c = ConfigEditor.setRespectFocus(c, true)
            c = try ConfigEditor.setMonthlyTokens(c, 0)
            c = ConfigEditor.setPauseAtBudget(c, true)
            c = ConfigEditor.setDryRun(c, false)
            return ConfigEditor.setHotkey(c, .on)
        }
    }

    // MARK: Toast

    /// Shows a short message at the bottom of the pane for 1.8 s. A new one replaces it.
    func toast(_ text: String) {
        toastText = text
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .milliseconds(1800))
            if !Task.isCancelled { toastText = nil }
        }
    }

    // MARK: Sound

    /// Plays the chosen notification sound once. None plays nothing.
    func preview(_ sound: NotifySound) {
        guard sound != .none else { return }
        NSSound(named: NSSound.Name(sound.rawValue.capitalized))?.play()
    }

    // MARK: Shortcut

    /// Turns the shortcut on or off. The registration changes only after the config save succeeds. A custom shortcut
    /// comes back as it was.
    func toggleHotkey(_ store: Store) {
        let current = store.snap.config?.hotkey ?? .on
        if current.isOn {
            if case .custom(let text) = current { rememberedShortcut = text }
            commit("hotkey", store: store, onSaved: { GlobalHotkey.shared.unregister(); return nil }) { ConfigEditor.setHotkey($0, .off) }
            return
        }
        let setting = rememberedShortcut.map(HotkeySetting.custom) ?? .on
        saveShortcut(setting, text: rememberedShortcut ?? "⌥⌘G", restore: current, store: store)
    }

    /// Saves a shortcut setting, then registers it. When the system refuses it, the previous registration comes back and
    /// the row says why; the setting stays saved.
    private func saveShortcut(_ setting: HotkeySetting, text: String, restore: HotkeySetting, store: Store, toast: String? = nil) {
        commit("hotkey", store: store, toast: toast, onSaved: {
            if let spec = HotkeySpec.from(setting), GlobalHotkey.shared.register(spec) { return nil }
            GlobalHotkey.shared.apply(restore)
            return "Another app already uses \(text), so Glidepath cannot register it."
        }) { ConfigEditor.setHotkey($0, setting) }
    }

    /// Starts listening for one key combination. The next keydown with ⌘, ⌃ or ⌥ is the shortcut; Esc cancels.
    func startRecording(_ store: Store) {
        guard !recording else { return }
        recording = true
        rowErrors["hotkey"] = nil
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handleKey(event, store: store) }
            return nil
        }
    }

    func stopRecording() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        recording = false
    }

    private func handleKey(_ event: NSEvent, store: Store) {
        if event.keyCode == 53 {
            stopRecording()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else { return }
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        text += (event.charactersIgnoringModifiers ?? "").uppercased()
        stopRecording()
        guard HotkeySpec.parse(text) != nil else {
            rowErrors["hotkey"] = "Use a letter or a digit after ⌘, ⌃ or ⌥."
            return
        }
        let current = store.snap.config?.hotkey ?? .on
        saveShortcut(.custom(text), text: text, restore: current, store: store, toast: "Shortcut set to \(text)")
    }

    // MARK: Config file drawer

    /// Reads config.toml as it is on disk. Lines that were not in the last read are marked for 1.6 s.
    func loadToml(_ paths: Paths) {
        let text = (try? String(contentsOfFile: paths.configFile, encoding: .utf8)) ?? "# No config yet. Run glidepath init."
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let before = Set(tomlLines)
        let changed = tomlLines.isEmpty ? Set<Int>() : Set(lines.indices.filter { !before.contains(lines[$0]) })
        tomlLines = lines
        tomlChanged = changed
        highlightTask?.cancel()
        guard !changed.isEmpty else { return }
        highlightTask = Task {
            try? await Task.sleep(for: .milliseconds(1600))
            if !Task.isCancelled { withAnimation(.easeOut(duration: 0.6)) { tomlChanged = [] } }
        }
    }

    // MARK: Login item and tools

    /// Flips the login item, then reads the live value back, since the system may refuse the change.
    func toggleLogin(_ store: Store) {
        store.setLoginItem(!loginOn)
        loginOn = store.loginItemOn
        rowErrors["login"] = store.actionError
    }

    /// Runs `Checks.tools(env:)` and `Checks.installed(paths)` off the main thread. Shows "Checking…" until they return.
    func runChecks(_ paths: Paths) {
        guard !checking else { return }
        checking = true
        tools = []
        Task {
            let items = await Task.detached { Checks.tools(env: Runner.environment(paths)) + Checks.installed(paths) }.value
            tools = items
            checking = false
        }
    }

    /// Puts a fix command on the pasteboard.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Opens the fix commands for `items` in Terminal, then checks again once Glidepath is active.
    func fix(_ items: [Checks.Item], _ paths: Paths) {
        guard FixInTerminal.open(items) else { return }
        Task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                runChecks(paths)
                return
            }
        }
    }

    // MARK: Files

    /// Opens the config. When there is none, writes the commented template first (the one `Store.editRepos` wrote).
    func openConfig(_ paths: Paths) {
        let path = paths.configFile
        if !FileManager.default.fileExists(atPath: path) {
            let empty = Config(schedule: Config.defaultSchedule.compactMap(ScheduleTime.init), limits: Limits(), repos: [])
            let template = "# Glidepath config. Add one [[repo]] table per repository to review.\n" + empty.render()
            try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                     withIntermediateDirectories: true)
            try? template.write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    /// Selects the state folder in Finder, creating it first so there is something to select.
    func revealStateFolder(_ paths: Paths) {
        try? FileManager.default.createDirectory(atPath: paths.stateDir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: paths.stateDir)])
    }

    // MARK: Uninstall

    /// Runs `glidepath uninstall` with the job's environment, output appended to the log. Called only after confirm.
    func uninstall(_ store: Store) {
        guard let binary = Bundle.main.executablePath else {
            rowErrors["uninstall"] = "cannot find the glidepath binary"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["uninstall"]
        process.environment = Runner.environment(store.paths)
        let logPath = store.paths.logFile
        try? FileManager.default.createDirectory(atPath: (logPath as NSString).deletingLastPathComponent,
                                                 withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil)
        }
        if let log = FileHandle(forWritingAtPath: logPath) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        }
        process.terminationHandler = { [weak self] p in
            let ok = p.terminationStatus == 0
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.finishUninstall(ok: ok, store: store) } }
        }
        rowErrors["uninstall"] = nil
        do {
            try process.run()
            uninstalling = true
        } catch {
            rowErrors["uninstall"] = "run failed: \(error.localizedDescription)"
        }
    }

    /// The uninstall ended: a success says what is left to do by hand; a failure points at the log. Then reloads, so
    /// the job and the skill read as gone.
    private func finishUninstall(ok: Bool, store: Store) {
        uninstalling = false
        if ok {
            uninstallNote = "Glidepath's job, skill and app link are removed. Quit Glidepath, then run brew uninstall glidepath."
        } else {
            rowErrors["uninstall"] = "Uninstall failed. See the log."
        }
        store.reload()
    }
}

/// Runs fix commands in Terminal: the script goes to a temporary `.command` file, which Terminal opens.
enum FixInTerminal {
    /// False when there is nothing to run or the file cannot be written.
    @discardableResult
    static func open(_ items: [Checks.Item]) -> Bool {
        guard let script = Checks.fixScript(items) else { return false }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("glidepath-fix-\(UUID().uuidString).command")
        do {
            try script.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        } catch {
            return false
        }
        return NSWorkspace.shared.open(url)
    }
}
