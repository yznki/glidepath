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
    /// The Claude account line under "Claude account": the signed-in email and plan, or why it is not known.
    @Published private(set) var accountStatus: String?
    /// The Linear row: whether a key is in the Keychain (read on refresh, never in snapshots), and the typed key.
    @Published private(set) var linearSaved: Bool?
    @Published var linearDraft = ""
    /// The Playbook section: the repo shown (nil until the first refresh picks a tended one), its playbook, the lesson whose
    /// Edit field is open (by identity: text, source and date), that field's text, and the teach field's text.
    @Published var playbookRepo: String?
    @Published private(set) var playbook: Playbook?
    @Published private(set) var editingLesson: Playbook.Lesson?
    @Published var lessonDraft = ""
    @Published var teachDraft = ""

    private var keyMonitor: Any?
    private var toastTask: Task<Void, Never>?
    private var highlightTask: Task<Void, Never>?
    /// The custom shortcut text last switched off, so turning the shortcut back on restores it.
    private var rememberedShortcut: String?

    /// The UserDefaults keys the look rows own. Reset clears them with the config keys.
    static let lookKeys = ["glyphStyle", "glyphBadge", "signalColour", "glassBlur", "motion"]

    /// `query` starts the search: snapshot rendering uses it to show one group.
    init(query: String = "") {
        self.query = query
    }

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
        refreshAccount(store, dir: store.snap.config?.claudeConfigDir)
        // Snapshots never reach the Keychain: the fixture's Linear state comes from the snapshot.
        linearSaved = store.isFixture ? nil : LinearKey.read() != nil
        if playbookRepo == nil { playbookRepo = store.snap.config?.repos.first(where: \.tend)?.slug }
        playbook = playbookRepo.map { store.playbook($0) }
        if store.isFixture {
            tools = store.snap.tools ?? []
            return
        }
        runChecks(store.paths)
    }

    /// Reads the signed-in account of `dir` (or the user's own when nil) with `claude auth status`, off the main thread.
    /// Fixtures show a fixed line: they never run claude.
    func refreshAccount(_ store: Store, dir: String?) {
        guard !store.isFixture else {
            accountStatus = "you@example.com · max"
            return
        }
        let paths = store.paths
        Task {
            accountStatus = await Task.detached { ClaudeAccount.status(dir: dir, paths: paths) }.value
        }
    }

    /// Switches between the user's own Claude sign-in and a separate account. A separate account gets its folder, and
    /// Terminal opens to sign it in.
    func chooseAccount(separate: Bool, store: Store) {
        // The choice already in effect: nothing to write, and no Terminal.
        guard (store.snap.config?.claudeConfigDir != nil) != separate else { return }
        let paths = store.paths
        let dir = ClaudeAccount.dir(paths)
        commit("account", store: store, onSaved: { [weak self] in
            let error = separate ? ClaudeAccount.adopt(dir: dir, home: paths.home) : nil
            self?.refreshAccount(store, dir: separate ? dir : nil)
            return error
        }) { ConfigEditor.setClaudeAccount($0, separate: separate, home: paths.home) }
    }

    /// Opens Terminal to sign the separate account in again.
    func signIn(_ store: Store) {
        let dir = ClaudeAccount.dir(store.paths)
        guard FixInTerminal.open(script: ClaudeAccount.signInScript(dir: dir)) else {
            rowErrors["account"] = "Could not open Terminal to sign in."
            return
        }
        rowErrors["account"] = nil
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
    // MARK: Linear

    /// Saves the typed key to the Keychain. The field clears on success. Snapshots never write the Keychain.
    func saveLinearKey(_ store: Store) {
        let key = linearDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !store.isFixture else { return }
        do {
            try LinearKey.save(key)
            linearDraft = ""
            linearSaved = true
            rowErrors["linear"] = nil
        } catch {
            rowErrors["linear"] = "Could not save the key: \(error)"
        }
    }

    func removeLinearKey(_ store: Store) {
        guard !store.isFixture else { return }
        LinearKey.remove()
        linearSaved = false
        rowErrors["linear"] = nil
    }

    // MARK: Playbook

    /// Shows another repo's playbook. An open lesson edit is dropped.
    func selectPlaybookRepo(_ slug: String, store: Store) {
        playbookRepo = slug
        editingLesson = nil
        playbook = store.playbook(slug)
    }

    func beginEdit(_ lesson: Playbook.Lesson) {
        editingLesson = lesson
        lessonDraft = lesson.text
    }

    func cancelEdit() {
        editingLesson = nil
        lessonDraft = ""
    }

    /// Saves the open lesson's new text. The lesson is found on disk by its identity, so an edit lands on the right lesson
    /// even when the list changed. Blank text keeps the edit open.
    func saveEdit(_ store: Store, slug: String) {
        guard let target = editingLesson else { return }
        let text = lessonDraft.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        var book = store.playbook(slug)
        guard let i = book.lessons.firstIndex(of: target) else { return cancelEdit() }
        book.lessons[i].text = text
        cancelEdit()
        savePlaybook(book, slug, store)
    }

    func deleteLesson(_ lesson: Playbook.Lesson, _ store: Store, slug: String) {
        savePlaybook(store.playbook(slug).remove(lesson), slug, store)
    }

    /// Adds the teach field's text as a lesson the user taught.
    func teach(_ store: Store, slug: String) {
        let text = teachDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        teachDraft = ""
        savePlaybook(store.playbook(slug).teach(text, source: "you taught", date: Date()), slug, store)
    }

    /// Writes the repo's playbook. Snapshots show the change without writing it. The shown copy is read from disk after the
    /// save, so it is what the file holds.
    private func savePlaybook(_ book: Playbook, _ slug: String, _ store: Store) {
        guard !store.isFixture else {
            playbook = book
            return
        }
        do {
            try book.save(slug, paths: store.paths)
            rowErrors["playbook"] = nil
        } catch {
            rowErrors["playbook"] = "Could not save the playbook: \(error.localizedDescription)"
        }
        playbook = store.playbook(slug)
    }

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
        return open(script: script)
    }

    /// Writes `script` to a temporary `.command` file and opens it in Terminal. False when the file cannot be written.
    @discardableResult
    static func open(script: String) -> Bool {
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

/// The separate Claude account: its sign-in folder, the user's skills linked into it, and the sign-in and status calls
/// that run with `CLAUDE_CONFIG_DIR` pointing there. The config's `claude_config_dir` names the folder.
enum ClaudeAccount {
    /// `~/.config/glidepath/claude`, the folder a separate account signs in to.
    static func dir(_ paths: Paths) -> String {
        paths.home + "/.config/glidepath/claude"
    }

    /// Creates the folder, and links `skills` in it to `~/.claude/skills` when nothing is there yet. Then opens Terminal to
    /// sign in. Returns a message when something failed, else nil.
    static func adopt(dir: String, home: String) -> String? {
        let fm = FileManager.default
        do {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let link = dir + "/skills"
            // A symlink that is already there, even a broken one, is left as it is.
            if !fm.fileExists(atPath: link), (try? fm.destinationOfSymbolicLink(atPath: link)) == nil {
                try fm.createSymbolicLink(atPath: link, withDestinationPath: home + "/.claude/skills")
            }
        } catch {
            return "Could not set up the account folder: \(error.localizedDescription)"
        }
        guard FixInTerminal.open(script: signInScript(dir: dir)) else {
            return "Could not open Terminal to sign in."
        }
        return nil
    }

    /// The Terminal script that signs the account in to `dir`.
    static func signInScript(dir: String) -> String {
        "#!/bin/sh\nCLAUDE_CONFIG_DIR='\(dir)' claude auth login\n"
    }

    /// "email · plan" from `claude auth status --json` run with `dir` (or the user's own when nil). Off the main thread.
    static func status(dir: String?, paths: Paths) -> String {
        var env = Runner.environment(paths)
        if let dir { env["CLAUDE_CONFIG_DIR"] = dir }
        let result = Shell.run("claude", ["auth", "status", "--json"], env: env, timeout: 30)
        guard result.ok, let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Not signed in, or claude is not installed"
        }
        let parts = [json["email"] as? String, json["subscriptionType"] as? String].compactMap { $0 }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "Signed in" : parts.joined(separator: " · ")
    }
}
