import SwiftUI
import AppKit

/// The Settings section (no mockup; built from the Repos pattern): notifications, updates, open at login, the tools
/// checks, advanced files, and uninstall last. Switches save at once through `ConfigEditor`; the login item applies at
/// once. The tools checks run off the main thread each time the section appears, and on "Check again".
struct SettingsView: View {
    @ObservedObject var store: Store
    @StateObject private var model = SettingsModel()

    private var config: Config? { store.snap.config }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TitleRow(saved: model.saved)
            WinScroll {
                VStack(alignment: .leading, spacing: 0) {
                    SettingRow(title: "Notifications", detail: "Posts a notification when a sweep finishes.",
                               error: model.rowErrors["notify"]) {
                        WinToggle(isOn: config?.notify ?? true) {
                            model.commit("notify", store: store) { ConfigEditor.setNotify($0, !($0.notify)) }
                        }
                    }
                    updatesRow
                    SettingRow(title: "Automatic checks", detail: "Check for updates automatically in the background.",
                               error: model.rowErrors["autoUpdates"]) {
                        WinToggle(isOn: config?.checkUpdates ?? true) {
                            model.commit("autoUpdates", store: store) { ConfigEditor.setCheckUpdates($0, !($0.checkUpdates)) }
                        }
                    }
                    SettingRow(title: "Open Glidepath with ⌥⌘G", detail: "Opens the menu bar popover from any app.",
                               error: model.rowErrors["hotkey"]) {
                        WinToggle(isOn: config?.hotkey ?? true) { model.toggleHotkey(store) }
                    }
                    SettingRow(title: "Open at login", detail: "Starts Glidepath when you log in.",
                               error: model.rowErrors["login"]) {
                        WinToggle(isOn: model.loginOn) { model.toggleLogin(store) }
                    }
                    toolsRow
                    advancedRow
                    uninstallSection
                }
                .padding(.bottom, WinMetrics.canvasBottom)
            }
        }
        .padding(.top, WinMetrics.titlebarZone)
        .padding(.leading, WinMetrics.canvasLeft)
        .padding(.trailing, WinMetrics.canvasRight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { model.refresh(store) }
    }

    // MARK: Updates

    /// The version, the check, and the update on offer (primary, as the one filled control on the screen).
    private var updatesRow: some View {
        SettingRow(title: "Updates", detail: "Checks GitHub for new releases.", error: model.rowErrors["updates"]) {
            VStack(alignment: .leading, spacing: WinMetrics.s8) {
                HStack(spacing: WinMetrics.s12) {
                    Text("Glidepath \(Version.current)")
                        .font(.system(size: 13))
                        .foregroundStyle(WinTheme.text)
                        .monospacedDigit()
                    WinButton(title: "Check for updates", style: .outline) { store.checkForUpdates(manual: true) }
                        .disabled(store.snap.updateChecking)
                }
                if let update = store.availableUpdate {
                    WinButton(title: "Update to \(update.latest)…", style: .primary) { confirmUpdate(update) }
                        .disabled(store.snap.updatePhase == .updating)
                        .padding(.top, WinMetrics.s4)
                }
                if store.snap.updatePhase == .failed {
                    Text("Update failed. See the log.")
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.amberInk)
                } else if let note = store.snap.updateNote {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(WinTheme.faint)
                }
            }
        }
    }

    /// The same confirm as the popover's Update: Homebrew installs in place; anything else opens the release page.
    private func confirmUpdate(_ update: UpdateCache) {
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

    // MARK: Tools

    /// The onboarding tools list, live: each check with its status, and the fix with Copy for anything missing.
    private var toolsRow: some View {
        SettingRow(title: "Tools", detail: "Checked live. A missing one shows the command that fixes it.",
                   error: model.rowErrors["tools"]) {
            VStack(alignment: .leading, spacing: WinMetrics.s12) {
                if model.tools.isEmpty {
                    Text("Checking…")
                        .font(.system(size: 13))
                        .foregroundStyle(WinTheme.muted)
                } else {
                    ForEach(Array(model.tools.enumerated()), id: \.offset) { _, item in
                        toolLine(item)
                    }
                }
                WinButton(title: "Check again", style: .outline) { model.runChecks(store.paths) }
                    .disabled(model.checking)
            }
        }
    }

    /// One check: a 20 pt mark, the name, and for a missing one the fix in mono with Copy.
    private func toolLine(_ item: Checks.Item) -> some View {
        HStack(alignment: .top, spacing: WinMetrics.s12) {
            ZStack {
                Circle().fill(item.ok ? WinTheme.green : WinTheme.amber)
                Image(systemName: item.ok ? "checkmark" : "exclamationmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(item.ok ? Color.white : WinTheme.text)
            }
            .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13))
                    .foregroundStyle(WinTheme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.ok {
                    // Copy sits right after the command, 12 pt on, so it reads as the command's button.
                    HStack(alignment: .center, spacing: WinMetrics.s12) {
                        Text(item.fix)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WinTheme.muted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        WinButton(title: "Copy", style: .outline, small: true) { model.copy(item.fix) }
                    }
                }
            }
        }
    }

    // MARK: Advanced

    /// The files and folders Glidepath keeps, each opened in Finder or the default app.
    private var advancedRow: some View {
        SettingRow(title: "Advanced", detail: "The config, the log and the state folder.", error: model.rowErrors["advanced"]) {
            HStack(spacing: WinMetrics.s8) {
                WinButton(title: "Open config file", style: .outline) { model.openConfig(store.paths) }
                WinButton(title: "Open log", style: .outline) { store.openLog() }
                WinButton(title: "Reveal state folder", style: .outline) { model.revealStateFolder(store.paths) }
            }
        }
    }

    // MARK: Uninstall

    /// Last, under a rule: the one destructive action, in the error colour. It asks first.
    private var uninstallSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Uninstall Glidepath…") { confirmUninstall() }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WinTheme.red)
                .disabled(model.uninstalling)
                .frame(height: 32, alignment: .leading)
            if let note = model.uninstallNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error = model.rowErrors["uninstall"] {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(WinTheme.amberInk)
            }
        }
        .padding(.vertical, WinMetrics.s16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(WinTheme.line).frame(height: 1)
        }
        .padding(.top, WinMetrics.s16)
    }

    /// Names what goes, then runs `glidepath uninstall` only on confirm.
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Uninstall Glidepath?"
        alert.informativeText = "This removes the scheduled job, the skill in ~/.claude/skills/glidepath, the app link in "
            + "~/Applications, and the login item. Your config and state stay. Clones are not touched. "
            + "Glidepath itself comes from Homebrew: run brew uninstall glidepath to remove it."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        model.uninstall(store)
    }
}

/// The title row at the titlebar zone: "Settings" 24 bold, and the Saved stamp for the switches. Observes the stamp
/// itself, because a flash on a child object does not redraw the parent.
private struct TitleRow: View {
    @ObservedObject var saved: SavedFlash

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: WinMetrics.s12) {
            Text("Settings")
                .font(.system(size: 24, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(WinTheme.text)
                .frame(height: 32, alignment: .leading)
            SavedStamp(shown: saved.shown)
        }
        .padding(.bottom, WinMetrics.s24)
    }
}

/// The Settings section's state: the live login item and tool checks, per-row messages, and the uninstall run.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var rowErrors: [String: String] = [:]
    @Published private(set) var loginOn = false
    @Published private(set) var tools: [Checks.Item] = []
    @Published private(set) var checking = false
    @Published private(set) var uninstalling = false
    @Published private(set) var uninstallNote: String?
    let saved = SavedFlash()

    /// Reads the live login item and runs the tool checks.
    func refresh(_ store: Store) {
        loginOn = store.loginItemOn
        if store.isFixture {
            tools = store.snap.tools ?? []
            return
        }
        runChecks(store.paths)
    }

    /// Turns the ⌥⌘G shortcut on or off. Turning it on registers the shortcut first: when the system refuses it, the
    /// setting stays off and the row says why.
    func toggleHotkey(_ store: Store) {
        let on = !(store.snap.config?.hotkey ?? true)
        if on {
            guard GlobalHotkey.shared.register() else {
                rowErrors["hotkey"] = "Another app already uses ⌥⌘G, so Glidepath cannot register it."
                return
            }
        } else {
            GlobalHotkey.shared.unregister()
        }
        commit("hotkey", store: store) { ConfigEditor.setHotkey($0, on) }
    }

    /// Runs `Checks.tools()` and `Checks.installed(paths)` off the main thread. Shows "Checking…" until they return.
    func runChecks(_ paths: Paths) {
        guard !checking else { return }
        checking = true
        tools = []
        Task {
            let items = await Task.detached { Checks.tools() + Checks.installed(paths) }.value
            tools = items
            checking = false
        }
    }

    /// Puts a fix command on the pasteboard.
    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Flips the login item, then reads the live value back, since the system may refuse the change.
    func toggleLogin(_ store: Store) {
        store.setLoginItem(!loginOn)
        loginOn = store.loginItemOn
        rowErrors["login"] = store.actionError
    }

    /// Applies one switch to the saved config and writes it. On success the store reloads and the Saved stamp shows.
    /// On failure the message goes to `row` and nothing is written.
    /// The change is applied to config.toml as it is on disk now (ConfigWriter), so a hand edit since the window
    /// loaded the file is kept, and the write runs off the main actor.
    func commit(_ row: String, store: Store, _ change: @escaping @Sendable (Config) throws -> Config) {
        let paths = store.paths
        Task {
            do {
                try await ConfigWriter.shared.apply(paths: paths, change: change) { try ConfigEditor.save($0, paths: paths) }
                rowErrors[row] = nil
                saved.flash()
            } catch let error as ConfigError {
                rowErrors[row] = error.message
            } catch {
                rowErrors[row] = "Could not save: \(error.localizedDescription)"
            }
            store.reload()
        }
    }

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
