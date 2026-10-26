# Code map: UI layer, v1.10

Source: `origin/main` at `1eff468` ("progress: 1.10 released"), read from a detached worktree. Not the checked-out `sdlc-plan` branch. Line numbers are for that commit. Read-only; no code changed.

Scope: `Sources/Glidepath/App`, `Sources/Glidepath/Window`, `Sources/Glidepath/UI`, `Sources/Glidepath/main.swift`, plus the Core/CLI symbols the UI touches. Core and CLI are listed only where the UI depends on them.

---

## 1. Build and packaging

**Package.swift**

- `// swift-tools-version:5.9` (Package.swift:1).
- Platform: `.macOS(.v14)` (Package.swift:6). Formula also says `depends_on macos: :sonoma` (Formula/glidepath.rb:9). Info.plist says `LSMinimumSystemVersion` `14.0` (Resources/Info.plist:21-22).
- Products: one executable, `glidepath`, from target `Glidepath` (Package.swift:8).
- Targets: `executableTarget "Glidepath"` at `Sources/Glidepath` (Package.swift:11). `testTarget "GlidepathTests"` at `Tests/GlidepathTests`, depends on `Glidepath` (Package.swift:12).
- External dependencies: none. No `dependencies:` entries. Everything is Apple SDK (SwiftUI, AppKit, Carbon.HIToolbox, ServiceManagement, UserNotifications, ImageIO, UniformTypeIdentifiers) plus Foundation.

**make-app.sh** (the bundle step, used by Homebrew and by hand)

- `swift build -c release` unless `--no-build` is passed (make-app.sh:8).
- Copies `.build/release/glidepath` to `build/Glidepath.app/Contents/MacOS/glidepath` (make-app.sh:20).
- Copies `Resources/Info.plist` into the bundle (make-app.sh:21).
- Sets `CFBundleShortVersionString` and `CFBundleVersion` from `static let current` in `Core/Version.swift` (make-app.sh:23-26). The checked-in Info.plist says `1.10.0` (Resources/Info.plist:17-18), so the script is the source of truth at build time.
- Builds the icon: `sips` from `assets/brand/icon-small.png` and `icon.png`, then `iconutil -c icns` (make-app.sh:28-37).
- `codesign --force --deep -s - "$APP"`: ad-hoc signature (make-app.sh:39). No entitlements file exists in the repo; `Resources/` holds only `Info.plist`.

**Info.plist** (Resources/Info.plist)

- `CFBundleIdentifier` `dev.glidepath.app`, `CFBundleExecutable` `glidepath`, `CFBundleIconFile` `AppIcon`.
- `LSUIElement` = `true` (Resources/Info.plist:23-24). The app has no Dock icon as a menu bar app. `MainWindowLifecycle` switches the activation policy to `.regular` while the main window is open (Window/MainWindow.swift:117-143), and to `.accessory` again on close.

**Formula/glidepath.rb**

- Builds from the release tarball. Install step: `swift build --disable-sandbox -c release` (Formula:12), then `./make-app.sh --no-build` (Formula:13).
- Installs `build/Glidepath.app` into the keg prefix, the binary into `bin`, and `skill/glidepath/*` into `share/glidepath` (Formula:14-16).
- `glidepath init` then links the app into `~/Applications` (caveats text, Formula:20-35).

**CI**: `.github/workflows/ci.yml` runs `swift build` and `swift test` on `macos-latest`. It does not build the bundle.

---

## 2. File table: `Sources/Glidepath/App`, `Window`, `UI`

Line counts from `wc -l` on origin/main. "Store" is `Store.shared` or a `Store` passed in. "Store actions" are methods on `Store` called from that file. Core types are in section 4.

### App/ (18 files, plus main.swift in §5)

| File | Lines | Role | Reads (Store/model) | Store actions called |
|---|---:|---|---|---|
| App/AppDelegate.swift | 63 | NSApplicationDelegate: quit waits up to 5 s for a pending schedule save; Dock badge from `waitingCount`; Dock menu (Open, Review now, Pause/Resume); reopen opens the window | `Store.shared.$snap`, `waitingCount`, `snap.running/jobInstalled/paused` | `togglePause()`; `Confirm.run` (Dock "Review now") |
| App/BriefingFile.swift | 21 | Reads `stateDir/tend/briefing.json`, written by the CLI once a day | none (Core `Briefing`, `TendStore`, `Paths`) | none |
| App/Confirms.swift | 79 | Confirm sheets shared by popover, Now, History, Repos and menus: Run now, Review, Stop, Discard | `store.snap.config`, `postsReviews`, `dryRunning` | `runNow(repo:)`, `review(_:)`, `stopRun()`, `discardDraft(_:)` |
| App/GlobalHotkey.swift | 92 | ⌥⌘G Carbon hotkey (`RegisterEventHotKey`). `PopoverToggle` clicks the `NSStatusBarButton` found by walking the status bar window's view tree (:76-91) | none directly | none (`Store.reload` calls `GlobalHotkey.shared.apply`, Store.swift:329) |
| App/HeroGIF.swift | 71 | README hero: renders the popover as a looping GIF with injected time (`--hero-gif`) | `Store(snapshot:)` fixture | none |
| App/ListNav.swift | 73 | Key → list-move mapping (`ListKey`, `ListMove`, `ListNav`). No state | none | none |
| App/MenuApp.swift | 502 | `GlidepathApp` scenes (MenuBarExtra + Window "main"); `Snapshotter` (PNG/HTML renders); `Fixtures` (popover fixtures) | `Store.shared`; `Store(snapshot:)` | none in the live app; `Snapshotter` only writes files |
| App/MenuBarLabel.swift | 244 | Menu bar glyph: `GlyphState`, `MenuGlyph` (image drawing), `SweepTicker` (`ObservableObject`) | `snap`, `glyph`, `availableUpdate`, `draftCount`, `snap.approach` | none |
| App/Notifier.swift | 95 | `UNUserNotificationCenter` posts: sweep done, PR landed, briefing. Best effort; failures logged once | `NotifySound` (Core) from config passed by Store | none (called by `Store.reload`, Store.swift:426-470) |
| App/Popover.swift | 797 | Menu bar popover: `PopoverView` (:191), `PopoverModel` (:6), `FillModel` (:23), `RunButton`, `PRRow`, `StackGeometry`, `HeaderCopy` (:103) | `@ObservedObject store`; `snap`, `strips`, `draftCount`, `availableUpdate`, `loginItemOn`, `updatesWithBrew` | `popoverOpened()`, `popoverClosed()`, `togglePause()`, `stopRun()`, `startUpdate()`, `checkForUpdates(manual:)`, `setLoginItem(_:)`, `openLog()` |
| App/Popover/Card.swift | 374 | Stack cards in the popover: `StackCard` (:65), `StackMoreStrip` (:39), `CardTiltModel` (:27); `Verdict`/`Strip` display extensions (:4, :15) | `PopoverModel` (`@ObservedObject`), `snap`, `strips`, `draftErrors` | `postDraft(_:)`, `discardDraft(_:)`, `reviewPR(_:)`, `reviewWarning(_:)` |
| App/Presentation.swift | 258 | Pure derivation of header kind, row status and notice text from `Snapshot`. Also called by the CLI dashboard and Core `RunDigest` (see §4) | `Snapshot`, `RunState`, `RepoState` | none |
| App/Profile.swift | 412 | PR "profile" marks and the `ApproachProfile` drawing; `ProfileMotion` (:135) | `Stage`, `Verdict`; `justLanded` via Store | none |
| App/ShortcutCommands.swift | 367 | SwiftUI `Commands` (`GlidepathCommands`, :252), `ShortcutContext` (:181), `ShortcutDispatch` (:204) | `Store.shared` (`snap.running/paused/config`); `WindowRouter.shared`; `ShortcutContext.shared` | `togglePause()`, `openLog()`, `checkForUpdates(manual: true)` |
| App/Shortcuts.swift | 327 | Table of every shortcut (`ShortcutAction` :5, `Shortcuts` :161). Read by menus and the ⌘/ sheet | none | none |
| App/Store.swift | 970 | The observable store and its `Snapshot` (see §3) | reads run files, config, drafts, tend state, pause, updates, playbooks, review text | see §3 |
| App/Theme.swift | 143 | Colour and metric tokens (`Palette`, `Metrics`, `WinTheme`, `WinMetrics`) | none | none |
| App/WindowFixtures.swift | 635 | Fixtures for window screens and onboarding steps. Used by snapshot rendering and by `SplitBuilderTests` | `Store(snapshot:)` | none |

### UI/ (6 files)

| File | Lines | Role | Reads | Store actions |
|---|---:|---|---|---|
| UI/Avatar.swift | 109 | GitHub avatar: fetches `github.com/<login>.png?size=96` (:34) and caches in `~/Library/Caches/Glidepath/avatars`, 7 days. `AvatarModel` (:45) | none | none (network + file write) |
| UI/Glass.swift | 138 | Glass card hover and specular state (`SpotModel` :4, `BreathModel` :98), `VerdictLight`, `View` extensions | none | none |
| UI/Gotham.swift | 39 | Gotham glass colour tokens | none | none |
| UI/HoldButton.swift | 76 | `HoldModel`: fill level and fired state for hold-to-confirm | none | none |
| UI/Motion.swift | 34 | Spring presets and reduced-motion switch | none | none |
| UI/Tracer.swift | 39 | Silver arc animation | none | none |

### Window/ (28 files)

| File | Lines | Role | Reads | Store actions |
|---|---:|---|---|---|
| Window/ApproachChart.swift | 395 | Approach chart layout and painter (`ApproachGeometry` :5, `ApproachFrame` :92, `ApproachPainter` :176). Pure layout | `ApproachPlane`, `ApproachPhase` (passed in) | none |
| Window/ApproachSection.swift | 1201 | Approach section: plane list, drawer, Needs-you rows, Edit-call sheet. Types: `ApproachSectionView` :9, `ApproachPopoverBlock` :293 (used by Popover), `TendNeedRow` :408, `ApproachDrawer` :570, `CallEditModel` :1000, `CallEditCard` :1044, `ApproachModel` :1143 | `store.snap`, `approachPlane`, `playbook`, `tendBusy`, `tendErrors`, `tendFailures`, `paths`, `dismissBriefing` | `tendCommand(...)` for land, revert, push, split, ping, retry, discard, dismiss, reply; `reload()`; `dismissBriefing()`. `ApproachModel` writes config (:1197), Playbook (:1174) and TendStore (:1183) directly; see §4 |
| Window/BriefingCard.swift | 81 | Morning briefing card at the top of Approach | `Briefing` (passed in) | none found |
| Window/Controls.swift | 330 | Window buttons and inputs: `WinButton` :5, `WinSegmented` :73, `WinToggle` :155, `SavedFlash` :175, `SettingRow` :205, `WinScroll` :265, `SnapshotTimeline` :318 | none | none |
| Window/FlightRecorder.swift | 1200 | Review sheet as a flight recorder: `RunArtifactsModel` :9, `FlightModel` :34, `ApproachView` :256, `ReviewSheet` :452, `ReviewDetail` :493 | `snap`, `draftBusy`, `draftErrors`, `actionError`, `paths`; `RunArtifacts` loaded from disk | `draftPreview(_:)`, `postDraft(_:)`, `reviewPR(_:)`, `reviewWarning(_:)`; `Confirm.review` (:781) |
| Window/HeroField.swift | 82 | Stripe field behind the onboarding finish (ported from kit.js) | none | none |
| Window/MainWindow.swift | 159 | `MainWindowView` :6 (`@ObservedObject` router and store), `WindowScreen` :25 (onboarding vs sidebar+canvas switch), `WindowConfigurator` :81, `MainWindowLifecycle` :117, `OpenWindowBridge` :146 | `WindowRouter.shared`, `Store.shared` | none; `MainWindowLifecycle` calls `ScheduleModel.flushLive(Store.shared)` on close |
| Window/Mark.swift | 80 | Glidepath logo (`GlidepathMark`, `MarkPart`) | none | none |
| Window/Now.swift | 389 | Now section: needs-you list, recent runs, Review menu | `snap`, `strips`, `draftBusy`, `approachPlane`, `reviewText`, `reviewWarning` | `postDraft(_:)`, `reviewText(...)`, `approachPlane(...)`; `Confirm.review` (:239) |
| Window/Onboarding.swift | 993 | Onboarding wizard: `OnboardingView` :8, `OnboardingRail` :340, `OnboardingModel` :629 (steps, tool checks, repo loading, config import, first sweep) | `store.paths`; `Checks`, `ToolStatus` | `store.reload()` (via model) |
| Window/OnboardingFinish.swift | 437 | Finish step and "Whose PRs" choice. `OnboardingSummary` :346, `OnboardingSetup.run` :408 (does the install work; see §4) | none (takes config from model) | none |
| Window/QuietHoursField.swift | 41 | Quiet-hours text field | own `Entry` | none |
| Window/RepoPicker.swift | 251 | GitHub repo list, shared by onboarding and Repos. `RepoCatalog` :7 and `PickerCursor` :65 are `ObservableObject`s. Calls `gh` through `RepoDiscovery` (:36-58) | `Runner.environment` | none |
| Window/Repos.swift | 828 | Repos section: `ReposView` :26, `RepoDetail` :260, `AddRepoSheet` :633, `ReposModel` :712 | `store.paths`, `snap`, `strips`; `RepoCatalog.shared` | `reload()`; `ReposModel.commit` writes config (:760) and rules file (:489) |
| Window/ReviewSheet.swift | 302 | "Review now" sheet: `ReviewNowSheet` :118, `ReviewSheetModel` :19. Loads PR lists through `Runner.openPRs` (gh, :68) | `store.paths`, `snap` | none on Store; `Runner` gh calls |
| Window/Reviews.swift | 280 | History: `HistoryView` :5, `ReviewRow` :90, `ReviewSweep` :139, `ReviewsModel` :180 | `allRuns()`, `isFixture`, `paths`, `reviewText`, `snap` | none |
| Window/RunCard.swift | 293 | Run card and its folds (`RunCard` :17, `RunFolds` :4) | `snap`, `draftErrors`, `liveTokens`; `RunDigest` | none |
| Window/Schedule.swift | 377 | Schedule section: `ScheduleView` :7, `ScheduleModel` :247 (`static weak var live` :257) | `allRuns()`, `paths`, `snap` | `reload()`; `ScheduleModel` writes config through `ConfigWriter` (:360) and `ScheduleEditor.save`; `setPause` writes pause state |
| Window/ScheduleControls.swift | 576 | Dial: `DialEditor` :7 (`ObservableObject`), `ScheduleDialView` :125, `PresetGrid` :171, `DayPills` :205, `DialView` :311 | `DialEditor` | none |
| Window/Settings.swift | 957 | Settings section: `SettingsView` :101, `SettingsCopy` :5 (labels, captions, search text) | `snap`, `strips`, `paths`, `availableUpdate`, `isFixture` | `checkForUpdates(manual:)`, `startUpdate()`, `openLog()`, `updatesWithBrew` |
| Window/SettingsLinear.swift | 48 | Linear key row. Key lives in Keychain (`LinearKey`) | `SettingsModel`, `snap` | via model |
| Window/SettingsModel.swift | 564 | `SettingsModel` :7 (`ObservableObject`): `commit`, toggles, shortcut recording, playbook editing, Claude account, uninstall, open config. `FixInTerminal` :495, `ClaudeAccount` :520 | `actionError`, `allRuns`, `isFixture`, `loginItemOn`, `paths`, `playbook`, `snap` | `reload()`, `setLoginItem(_:)`; `commit` writes config (:137); see §4 |
| Window/SettingsParts.swift | 417 | Shared setting controls: `SettingItem`, `SettingGroup`, `SettingSwitch`, `SettingSegmented`, `SettingSlider`, `SettingTags`, `SettingButton`, `BudgetRing`, `ConfigDrawer`, `SettingsToast`; `SliderDraft` :177 | `SliderDraft` | none |
| Window/SettingsPlaybook.swift | 159 | Per-repo playbook: read-only commands, editable lessons | `SettingsModel`, `snap` | via model |
| Window/ShortcutsSheet.swift | 102 | ⌘/ sheet: `ShortcutsSheet` :5, `ShortcutsModel` :100 | `Shortcuts` table | none |
| Window/Sidebar.swift | 129 | Sidebar: brand row, scope, five sections, next-sweep line | `router`, `snap`, `waitingCount` | none |
| Window/SplitBuilder.swift | 259 | Split builder: `SplitBuilderModel` :8, `SplitBuilderCard` :90 | `snap`, `tendBusy`, `tendErrors`, `tendFailures` | `tendCommand(["split", "build", ...])` (:80), `tendCommand(["split", "keep", ...])` (:144). Writes a temp JSON file (:73), removes it (:81) |
| Window/WindowRoot.swift | 107 | `WindowSection` enum (:5) and `WindowRouter` (:23), the window's route and launch logic | `Config`, `Paths`, `OnboardingResume` | `open(_:)`, `openReview(_:)`, `deliver(_:section:)`, `take(_:)`, `openOnboarding()`, `openAtLaunchIfUnconfigured()` |

Totals: App 18 files (7,041 lines counting Store at 970 and WindowFixtures at 635, Popover 797), UI 6 files (~600 lines), Window 28 files (~11,000 lines). Plus `main.swift` (28 lines). The biggest files are `ApproachSection.swift` (1201), `FlightRecorder.swift` (1200), `Onboarding.swift` (993), `Settings.swift` (957), `Store.swift` (970).

---

## 3. The store and view-models

**Kind.** Everything uses `ObservableObject` with `@Published`, `@StateObject` and `@ObservedObject`. There are no `@Observable` or `@State` macros in the UI layer. Popover.swift:4 says why: "SwiftUI's state wrappers are macros in the SDK and Command Line Tools cannot load" them. A rebuild that moves to `@Observable` has to change the build setup (full Xcode) first, which the Formula install path does not have.

### Store (App/Store.swift:174, `final class Store: ObservableObject`, `@MainActor`)

Published state (views observe these):

| Member | Line | Notes |
|---|---:|---|
| `snap: Snapshot` | :178 | `private(set)`. Everything the views draw. Read 122 times across views |
| `actionError: String?` | :182 | Last action error, shown until next reload |
| `justLanded: Set<String>` | :184 | `private(set)`. Stamps that landed while the popover was open |
| `hovered: String?` | :185 | Row hover id |
| `draftBusy: [String: DraftAction]` | :187 | `private(set)`. Post or discard running per row |
| `draftErrors: [String: String]` | :188 | `private(set)` |
| `tendFailures: [String: Int]` | :191 | `private(set)`. Count per Needs item; new count resets the hold button |
| `tendErrors: [String: String]` | :192 | `private(set)` |
| `tendBusy: Set<String>` | :194 | `private(set)`. Needs items with a tend command running |
| `liveTokens: (total: Int, byPR: [Int: Int])` | :196 | `private(set)`. Polled every 2 s from the transcript while a sweep runs |
| `jobError: String?` | :215 | `private(set)`. Failed launchd reinstall |

Non-published: `static let shared` (:175), `static let ackKey` (:176), `isFixture` (:180), `paths` (:200), `profileMotion` (:201), `popoverOpen` (:202, `var`).

Computed (derived from `snap`): `dryStrips` (:256), `strips` (:258), `waitingCount` (:268), `draftCount` (:271), `availableUpdate` (:274), `updatesWithBrew` (:280), `errorText` (:285), `headerKind` (:286), `changesWaiting` (:289), `glyph` (:294). `static strips(from:)` is at the end of the file.

Methods views call (with the number of view call sites from grep):

| Method | Line | One line |
|---|---:|---|
| `init(snapshot:justLanded:motion:)` | :228 | Live app when `snapshot == nil`: registers login item, watches folders, first `reload()`, hourly update check. Fixture otherwise |
| `reload()` | :306 | Reads run, config, pause, job, tend, drafts, landed, briefing; posts notices; calls `reconcileJob` and `syncLiveTokens`. 8 view call sites |
| `popoverOpened()` / `popoverClosed()` | :580 / :590 | Acknowledges the last finished run, reloads, checks updates if due |
| `setHovered(_:)` | :594 | Sets `hovered`. No view calls it (only Store) |
| `stopRun()` | :600 | Sends SIGTERM to the process group (`kill(-pid)`), marks the run finished |
| `postDraft(_:)` | :619 | Runs `glidepath drafts post <repo> <n>` |
| `discardDraft(_:)` | :627 | Runs `glidepath drafts discard <repo> <n>` |
| `reviewPR(_:)` | :637 | Runs `glidepath review <repo> <n>` for a PR skipped for size |
| `reviewWarning(_:)` | :647 | Confirm text for a PR over `max_changed_lines` |
| `draftPreview(_:)` | :653 | Verdict line and first 300 chars of the held draft, for the post confirm |
| `openDashboard()` | :702 | Runs `glidepath dashboard`. No UI caller found |
| `togglePause()` | :720 | `Pause.set` on disk, then reload |
| `runNow(repo:)` | :731 | Spawns `glidepath run [--repo slug]` |
| `review(_:)` | :738 | Spawns `glidepath review …` for a `ReviewTarget`. Refused while a sweep or dry run holds the lock |
| `tendCommand(_:item:timeout:onDone:)` | :788 | Runs `glidepath tend <args>` off main thread; one command per item; then reload |
| `approachPlane(_:_:)` | :825 | Lookup in `snap.approach` |
| `playbook(_:)` | :830 | Fixture playbook or `Playbook.load` from disk |
| `checkForUpdates(manual:)` | :839 | GitHub release check; caches `UpdateCache` |
| `checkIfDue(maxAge:)` | :864 | Runs the check if the cache is older than `maxAge` |
| `startUpdate()` | :879 | Runs `glidepath update --wait`; on success relaunches via `/bin/sh -c "sleep 1; open -n …"` then `NSApp.terminate` (:908-914) |
| `openLog()` | :919 | Opens the log file |
| `setLoginItem(_:)` | :923 | `SMAppService.mainApp` register or unregister |
| `loginItemOn` | :932 | Read of `SMAppService` status (or fixture value) |
| `allRuns()` | :935 | All run files, or fixture runs |
| `reviewText(runId:slug:n:)` | :941 | Review text from disk, or fixture |
| `dismissBriefing()` | :470 | Marks the briefing seen. Called from ApproachSection and Store |

Private but load-bearing: `readTend` (:390), `notifyNewNeeds` (:425), `notifyLanded` (:443), `notifyBriefing` (:456), `landedSeen` (:482), `syncLiveTokens` (:499), `scheduleDryRunCheck` (:528), `reconcileJob` (:541, internal), `runCommand` (:661), `finishDraftCommand` (:695), `spawn` (:749), `attachLog` (:770), `checkUpdates` helpers, `finishUpdate` (:902), `registerLoginItemIfMoved` (:948).

Members with no caller outside Store.swift: `openDashboard`, `dryStrips`, `errorText`, `setHovered`, `reconcileJob`, `profileMotion`. `jobError` is read only by `errorText`. These are candidates to delete or to keep as the rebuild's API.

### Other view-models (all `ObservableObject`)

| Type | File:line | Published members | Methods |
|---|---|---|---|
| `PopoverModel` | App/Popover.swift:6 | `loginOn`, `openID`, `openHeight`, `highlight`, `drag`, `gone` | `init` |
| `FillModel` | App/Popover.swift:23 | `level` | none |
| `SweepTicker` | App/MenuBarLabel.swift:132 | `progress` | `setRunning` |
| `ShortcutContext` | App/ShortcutCommands.swift:181 (`.shared`) | `repoSheetOpen`, `timeSheetOpen`, `repoSelected`, `repoStepShowing`, `pinSelected`, `reviewSelected`, `reviewCanPost`, `reviewCanDiscard`, `reviewIsLarge` | `setReview` |
| `CardTiltModel` | App/Popover/Card.swift:27 | `active`, `angle` | none |
| `WindowRouter` | Window/WindowRoot.swift:23 (`.shared`) | `section`, `reviewFocus`, `showOnboarding`, `showShortcuts`, `pending` | `open`, `openReview`, `deliver`, `take`, `openOnboarding`, `openAtLaunchIfUnconfigured` |
| `SettingsModel` | Window/SettingsModel.swift:7 | `rowErrors`, `query`, `loginOn`, `tools`, `checking`, `uninstalling`, `uninstallNote`, `toastText`, `usedTokens`, `recording`, `drawerOpen`, `tomlLines`, `tomlChanged`, `chip`, `resetCount`, `accountStatus`, `linearSaved`, `linearDraft`, `playbookRepo`, `playbook`, `editingLesson`, `lessonDraft`, `teachDraft` | `commit`, `refresh`, `refreshAccount`, `chooseAccount`, `signIn`, `refreshUsed`, `addFlag`, `removeFlag`, `resetSettings`, `toggleHotkey`, `saveShortcut`, `startRecording`, `stopRecording`, `loadToml`, `toggleLogin`, `saveLinearKey`, `removeLinearKey`, `selectPlaybookRepo`, `beginEdit`, `cancelEdit`, `saveEdit`, `deleteLesson`, `teach`, `savePlaybook`, `runChecks`, `fix`, `openConfig`, `revealStateFolder`, `uninstall`, `finishUninstall` |
| `ScheduleModel` | Window/Schedule.swift:247 | `error`, `sweepTokens` | `flush`, `flushAndWait`, `flushLive` (static), `loadHistory`, `sync`, `setPause`, `changed`, `save`, `hasPendingSave` (AppDelegate reads it) |
| `DialEditor` | Window/ScheduleControls.swift:7 | `window`, `days`, `custom`, `shake` | `load`, `matches`, `edit`, `moveStart`, `moveEnd`, `stepEvery`, `dragCentre`, `beginDrag`, `endDrag`, `apply`, `toggleDay` |
| `OnboardingModel` | Window/Onboarding.swift:629 | `state`, `toolRows`, `toolItems`, `checkingTools`, `search`, `loginText`, `message`, `copied`, `backupNote`, `liveStrips` | `advance`, `goBack`, `copy`, `checkTools`, `fixTools`, `loadRepos`, `toggleRepo`, `useConfigFile`, `addLogin`, `removeLogin`, `bindDial`, `runFirstSweep`, `refreshLive`, `turnOnSchedule`, `postNothingYet`, `finish` |
| `ReposModel` | Window/Repos.swift:712 | `selectedSlug`, `detailOpen`, `rowErrors`, `addingRepo`, `picked`, `pickerSearch`, `addText`, `confirmRemove`, `editingLogins`, `loginText`, `addingFlag`, `flagText`, `editingNote`, `noteText` | `select`, `openAddRepo`, `commit`, `remove`, `flashSaved` |
| `ApproachModel` | Window/ApproachSection.swift:1143 | `opened`, `teach`, `expanded` | `toggle`, `setAutopilot`, `teachRepo`, `setTending`, `save` |
| `CallEditModel` | Window/ApproachSection.swift:1000 | `item`, `text`, `posting` | `open`, `close`, `post` |
| `SplitBuilderModel` | Window/SplitBuilder.swift:8 | `shown`, `slug`, `n`, `title`, `parts`, `target`, `saveError`, `saveFailures` | `open`, `close`, `move`, `build` |
| `ReviewsModel` | Window/Reviews.swift:180 | `runs`, `sweeps`, `opened` | `load`, `show`, `open`, `focus`, `withPosted`, `days` |
| `ReviewSheetModel` | Window/ReviewSheet.swift:19 | `open`, `mode`, `repo`, `prText`, `search`, `selectedAuthor`, `authors`, `listing`, `failedRepos`, `error` | `show`, `load`, `target` |
| `FlightModel` | Window/FlightRecorder.swift:34 | `draw`, `waypoints`, `figures`, `goAround`, `fired`, `halo`, `hot`, `flashed`, `linkHot`, `reviewError` | `play`, `flash` |
| `RunArtifactsModel` | Window/FlightRecorder.swift:9 | `artifacts` | `init`, `load` |
| `RepoCatalog` | Window/RepoPicker.swift:7 (`.shared`) | `repos`, `repoList` | `preset`, `load` |
| `PickerCursor` | Window/RepoPicker.swift:65 | `slug` | none |
| `ShortcutsModel` | Window/ShortcutsSheet.swift:100 | `query` | none |
| `RunFolds` | Window/RunCard.swift:4 | `open` | `toggle` |
| `SavedFlash` | Window/Controls.swift:175 | `shown` | `flash` |
| `SliderDraft` | Window/SettingsParts.swift:177 | `value` | none |
| `QuietHoursField.Entry`, `SettingTags.Entry` | QuietHoursField.swift:11, SettingsParts.swift:210 | `text` | none |
| `AvatarModel` | UI/Avatar.swift:45 | `image` | none |
| `SpotModel` / `BreathModel` | UI/Glass.swift:4, :98 | `pointer`, `hovering` / `breathing` | none |
| `HoldModel` | UI/HoldButton.swift:4 | `level`, `pressing`, `fired` | none |

Views that take a store: `PopoverView` (Popover.swift:192 `@ObservedObject store`), `MenuBarLabel` (MenuBarLabel.swift:204), `NowView`, `ReposView`, `ScheduleView`, `HistoryView`, `SettingsView`, `ApproachSectionView`, `OnboardingView`, `Sidebar`, `ReviewSheet`, `RunCard`, `SplitBuilderCard`, `WindowScreen`, `MainWindowView`. Each is `@ObservedObject var store: Store` (or `@ObservedObject` for the model), with the exception of `ShortcutCommands`, which reads `Store.shared` directly (ShortcutCommands.swift:254).

---

## 4. The boundary: Core and CLI

### 4a. Core/CLI types the UI uses

Core never imports SwiftUI, AppKit, Carbon or UserNotifications (grep of `Core/` and `CLI/`: no hits). So the UI → Core direction is the only one for UI code, with two exceptions in 4c.

UI files and the Core/CLI types they reference (word match on the type name):

| UI file | Core / CLI types |
|---|---|
| App/Store.swift | `Approach`, `ApproachPlane`, `ApproachSnapshot`, `Briefing`, `CLI`, `Checks`, `Config`, `Draft`, `Drafts`, `InstallKind`, `Linear`, `NeedsItem`, `PRFilter`, `Paths`, `Pause`, `Playbook`, `Posting`, `ReviewTarget`, `ReviewText`, `ReviewTextRecord`, `RunLock`, `RunState`, `RunStore`, `Runner`, `ScheduleEditor`, `ScheduleTime`, `ScheduleTimes`, `Shell`, `Split`, `SplitPlan`, `TendLanded`, `TendPR`, `TendStore`, `TowerLine`, `Transcript`, `UpdateCache`, `Updates`, `Verdict`, `Version`, `YourCall` |
| App/Presentation.swift | `RepoState`, `RunState`, `Stage` |
| App/Popover.swift | `Pause`, `RunDigest`, `UpdateCache`, `Verdict`, `Version` |
| App/Popover/Card.swift | `Draft`, `Verdict` |
| App/Confirms.swift | `ReviewTarget` (CLI/Run.swift:185) |
| App/GlobalHotkey.swift | `Config`, `HotkeySetting`, `HotkeySpec`, `Paths` |
| App/Notifier.swift | `NotifySound`, `Paths`, `Updates`, `Version` |
| App/BriefingFile.swift | `Briefing`, `RunStore`, `TendStore`, `Paths` |
| App/AppDelegate.swift | `Pause` |
| App/ShortcutCommands.swift, App/Shortcuts.swift | `Draft`, `Pause`, `Approach`, `Updates` (keyword hits; verify before relying on them) |
| App/WindowFixtures.swift | almost the whole Core model (`RunState`, `Config`, `ApproachSnapshot`, `TendPR`, `Playbook`, `Split*`, `ToolStatus`, `Seat`, etc.) |
| App/MenuApp.swift | `Approach`, `CLI`, `DashboardPage`, `Draft`, `DraftFile`, `Drafts`, `OnboardingStep`, `PRState`, `Paths`, `RunState`, `ScheduleTime`, `ScheduleTimes`, `Split`, `Stage`, `UpdateCache`, `Verdict` |
| Window/ApproachSection.swift | `Approach`, `ApproachPlane`, `ApproachSnapshot`, `Autopilot`, `Config`, `ConfigEditor`, `ConfigWriter`, `Council`, `CouncilRecord`, `GateState`, `Landing`, `NeedsItem`, `Playbook`, `Posting`, `RunDigest`, `RunState`, `Split`, `SplitPlan`, `TendConfig`, `TendPR`, `TendStore`, `ThreadVerdict`, `TowerLine` |
| Window/FlightRecorder.swift | `Approach`, `CheckerDelta`, `Draft`, `GitNexus`, `PRRef`, `Paths`, `PayloadComment`, `Posting`, `RepoConfig`, `ReviewTextRecord`, `RunArtifacts`, `Stage`, `Threads`, `Verdict` |
| Window/Now.swift | `Approach`, `NeedsItem`, `PRRef`, `Posting`, `RunDigest`, `RunState`, `Split` |
| Window/Onboarding.swift | `CLI`, `Checks`, `Claude`, `Config`, `ConfigEditor`, `ConfigError`, `ConfigSession`, `DiscoveredRepo`, `GitNexus`, `OnboardingResume`, `OnboardingState`, `OnboardingStep`, `Paths`, `Pause`, `RunState`, `RunStore`, `Runner`, `Shell`, `ShellResult`, `ToolStatus` |
| Window/OnboardingFinish.swift | `CLI`, `Config`, `ConfigEditor`, `ConfigError`, `GitNexus`, `InitCommand` (CLI/Init.swift:5), `InstallKind`, `Paths`, `Pause`, `Posting`, `RepoClone` (CLI/Run.swift:5), `Shell`, `ShellResult` |
| Window/Repos.swift | `Config`, `ConfigEditor`, `ConfigError`, `ConfigWriter`, `Draft`, `GitNexus`, `Posting`, `RepoConfig`, `RulesMode` |
| Window/Schedule.swift | `Config`, `ConfigError`, `ConfigWriter`, `DialFormat`, `DialPause`, `DialStats`, `DialUpcoming`, `Pause`, `RunState`, `ScheduleDays`, `ScheduleEditor`, `ScheduleTime` |
| Window/ScheduleControls.swift | `DialDays`, `DialFormat`, `DialPreset`, `DialUpcoming`, `DialWindow`, `ScheduleDays`, `ScheduleTime`, `Weekday` |
| Window/Settings.swift | `Ask`, `AuthorPolicy`, `Autopilot`, `Checks`, `Claude`, `Config`, `ConfigEditor`, `Draft`, `GitNexus`, `Landing`, `Lessons`, `Linear`, `NotifySound`, `Pause`, `Playbook`, `Posting`, `RepoConfig`, `ReviewModel`, `ScheduleEditor`, `Strictness`, `TendConfig`, `TendDisagree`, `TendJob`, `TendMerge`, `TendPush`, `Uninstall`, `UpdateCache`, `Updates`, `Version` |
| Window/SettingsModel.swift | `Checks`, `Claude`, `Config`, `ConfigEditor`, `ConfigError`, `ConfigWriter`, `HotkeySetting`, `HotkeySpec`, `Limits`, `Linear`, `LinearKey`, `NotifySound`, `Paths`, `Playbook`, `Runner`, `ScheduleTime`, `Shell`, `TokenBudget`, `Uninstall` |
| Window/SettingsLinear.swift, SettingsPlaybook.swift | `Linear`, `LinearKey`, `Lessons`, `Playbook` |
| Window/SplitBuilder.swift | `CLI`, `Split`, `SplitPart`, `SplitPlan` |
| Window/RepoPicker.swift | `Checks`, `ConfigError`, `DiscoveredRepo`, `Paths`, `RepoDiscovery`, `Runner` |
| Window/ReviewSheet.swift | `CLI`, `ConfigEditor`, `ConfigError`, `PRRef`, `ReviewTarget`, `Runner` |
| Window/Reviews.swift | `PRFilter`, `RunState`, `RunStore`, `Stage`, `Verdict` |
| Window/RunCard.swift | `PRFilter`, `PRRef`, `Posting`, `RunDigest`, `RunState`, `Stage` |
| Window/WindowRoot.swift | `Approach`, `Config`, `OnboardingResume`, `Paths` |
| Window/Sidebar.swift | `Version` |
| UI/* | none |

### 4b. UI code that does real work (a rebuild must preserve this)

Each item is a side effect that happens inside a view or view-model rather than in Core or the CLI:

1. **launchd job reinstall from the store.** `Store.reconcileJob` (Store.swift:541-566) calls `ScheduleEditor.installJob` on every reload when `jobNeedsReinstall`. It retries every 5 s while a run holds the lock (:567-578).
2. **Spawning the app's own binary** (`Bundle.main.executablePath`) with the job's environment (`Runner.environment`) and the log file attached: `glidepath run` (Store.swift:731), `review` (:738-770), `drafts post|discard` (:619-660, via a pipe and a termination handler), `tend <args>` (:788-823, `Shell.run` off main), `dashboard` (:702), `update --wait` (:879-900). Also `stopRun` sends `kill(-pid, SIGTERM)` and writes the run file (:600-617).
3. **Self-relaunch after update.** `finishUpdate` (Store.swift:902-917) starts `/bin/sh -c "sleep 1; /usr/bin/open -n $0"` on `paths.appLink`, then calls `NSApp.terminate`.
4. **Login item.** `SMAppService.mainApp` register/unregister (Store.swift:923-946), and `registerLoginItemIfMoved` re-registers when the bundle path changes (:948-958).
5. **Config writes.** Every settings edit and schedule save goes through `ConfigWriter.shared.apply(...) { ConfigEditor.save(...) }`: SettingsModel.commit (SettingsModel.swift:137), ReposModel.commit (Repos.swift:760), ScheduleModel (Schedule.swift:360), ApproachModel.save (ApproachSection.swift:1197). Config is also written directly in `openConfig` when the file is missing, via the commented template (SettingsModel.swift:430-436), and in onboarding `useConfigFile` (Onboarding.swift:773, `text.write(toFile:atomically:)`) and `OnboardingSetup.run` (OnboardingFinish.swift:425-437).
6. **Playbook and tend state written from the view-model.** `ApproachModel.teachRepo` writes `Playbook.save` (ApproachSection.swift:1174). `ApproachModel.setTending` writes `TendStore.save` (:1183). SettingsModel's playbook edits go through `savePlaybook` (SettingsModel.swift:382).
7. **Onboarding install.** `OnboardingSetup.run` (OnboardingFinish.swift:408-437) pauses the schedule if needed, `RepoClone.sync` (git clone or fetch) for each repo, installs the skill (`InitCommand.installSkill`), links the app (`linkApp`), writes the launchd plist (`InitCommand.installJob`, CLI/Init.swift:298), saves config, then runs a 3-PR dry run through `Shell.run` with a 3600 s timeout (:434).
8. **Tool checks and fixes.** `OnboardingModel.checkTools`/`fixTools` (Onboarding.swift:720-745) run `Checks` and `Shell.run` (:617, 30 s timeout). `ClaudeAccount.status` runs `claude auth status --json` (SettingsModel.swift:555) and `ClaudeAccount.adopt` creates the account dir, symlinks `skills`, and opens Terminal through `FixInTerminal.open`.
9. **Terminal scripts.** `FixInTerminal.open(script:)` writes a `.command` file to the temp dir with mode `0700` and opens it (SettingsModel.swift:500-515). Used for sign-in and fixes.
10. **Uninstall.** `SettingsModel.uninstall` spawns `glidepath uninstall` with the log attached (SettingsModel.swift:448-470).
11. **Keychain.** `LinearKey` saves and removes the Linear key (SettingsLinear.swift, SettingsModel `saveLinearKey` / `removeLinearKey`).
12. **Avatars.** `Avatar.swift:28-40` fetches from github.com and writes the cache file (7-day TTL).
13. **Repo discovery.** `RepoPicker` runs `RepoDiscovery.loadRepos` and `loadOpenCounts` (gh calls, RepoPicker.swift:36-58). `ReviewSheet` runs `Runner.openPRs` (ReviewSheet.swift:68). `Repos` writes the rules file template (Repos.swift:489).
14. **Split files.** `SplitBuilderModel.build` writes a temp JSON file, runs `tend split build --parts <file>` with a 7200 s timeout, then deletes the file (SplitBuilder.swift:73-82).
15. **Notifications.** `Notifier` posts through `UNUserNotificationCenter` (Notifier.swift); called from `Store.reload` and its notify helpers (Store.swift:306-470).
16. **Hotkey.** `GlobalHotkey.apply` (called on every reload, Store.swift:329) registers the Carbon hotkey. `PopoverToggle` clicks the SwiftUI status item by walking the status bar window's view tree (GlobalHotkey.swift:76-91). This depends on the private MenuBarExtra window class name containing "StatusBar".
17. **Snapshot writes.** `Snapshotter` writes PNG and HTML into a directory (MenuApp.swift:217-287). Runs only with `--snapshot`.

### 4c. Core/CLI depending on the UI (the reverse edge)

These must move or stay before the UI is rebuilt:

- **CLI/Dashboard.swift** uses `Snapshot` (Dashboard.swift:13, defined in App/Store.swift:64), `Presentation.headerKind` and `Presentation.failureMessage` (Dashboard.swift:21, :102; defined in App/Presentation.swift), and `HeaderCopy.make` (Dashboard.swift:21; defined in App/Popover.swift:103).
- **Core/RunDigest.swift:60** calls `Presentation.failureMessage(run)`. The `Strip` and `Presentation` matches at RunDigest.swift:14 are in a comment only.

So `Presentation.swift`, `Store.swift` (the `Snapshot` struct and `Strip`, Store.swift:26-125), and `HeaderCopy` in `Popover.swift` are shared with the CLI. A rebuild that deletes them breaks `glidepath dashboard` and the run digest. Move them to Core first, or keep them.

---

## 5. How the app starts

**Entry: `Sources/Glidepath/main.swift`** (28 lines). One binary for CLI and app.

- `argv == ["--unregister-login"]`: unregisters the login item and exits (main.swift:6-9). Called by `uninstall` through the app bundle.
- `argv.isEmpty` or `["app"]`: acquires `RunLock` on `stateDir/app.lock` (main.swift:11-23). If the lock is held, prints "already running" and exits 0. If the lock file cannot be created, starts anyway. Then `GlidepathApp.main()`.
- `argv.first` is `--snapshot` or `--hero-gif`: calls `GlidepathApp.main()` (main.swift:25-27). `GlidepathApp.init` handles both and exits.
- Otherwise `CLI.main(argv)` (main.swift:28).

**Scenes: `App/MenuApp.swift`**

- `struct GlidepathApp: App` (MenuApp.swift:5). `@NSApplicationDelegateAdaptor(GlidepathAppDelegate.self)` (:6).
- `init()` (:8-24): `--snapshot <dir>` renders and exits before any UI (:11-15). `GlobalHotkey.shared.applyConfig` on plain launch (:17-19). `--hero-gif <path>` renders the GIF and exits (:20-24).
- `body` (:28-44):
  - `MenuBarExtra { PopoverView(store: Store.shared) }` with `label: MenuBarLabel(store:)` and `.menuBarExtraStyle(.window)` (:29-36). The popover is a `.window`-style MenuBarExtra; the status item is an NSStatusBarButton in SwiftUI's status bar window.
  - `Window("Glidepath", id: "main") { MainWindowView() }` (:37-39), `.defaultSize(WinMetrics.windowWidth × windowHeight)`, `.windowStyle(.hiddenTitleBar)`, `.windowResizability(.contentMinSize)`, `.commands { GlidepathCommands() }` (:40-43).
  - **No `Settings` scene.** Settings is a section of the main window (`WindowSection.settings`, WindowRoot.swift:6, rendered at MainWindow.swift:70-72).
- `OpenWindowBridge` (MainWindow.swift:146-158) is placed in both the popover and the label. The label's copy calls `openAtLaunchIfUnconfigured()` once per launch.
- `GlidepathAppDelegate` (AppDelegate.swift:8) is attached with `@NSApplicationDelegateAdaptor`. It sets dark-aqua appearance (:12) and the Dock badge.

**Window routing: `Window/WindowRoot.swift`**

- `WindowSection` (:5-21): `now`, `approach`, `reviews` (title "History"), `repos`, `schedule`, `settings`. Sidebar order.
- `WindowRouter` (:23): `shared`, `section`, `showOnboarding`. `init` sets `showOnboarding = needsSetup()` (:40-42).
- `needsSetup(paths:forSection:)` (:46-52): true when config is missing, has no repos, or (when the window is opened without a section) a first sweep failed and was not retried (`OnboardingResume.failedSweep`).
- `open(_:)` (:65-73): selects a section, sets onboarding if needed, sets activation `.regular`, calls `openAction("main")`, activates the app.
- Onboarding routing: `WindowScreen` shows `OnboardingView` (no sidebar) when `router.showOnboarding` (MainWindow.swift:38-46). Otherwise `Sidebar` + canvas.

**Popover setup link:** `WindowRouter.openOnboarding()` (WindowRoot.swift:94-98) is called from the popover's "Set up Glidepath…".

**Snapshot (`--snapshot`)**

- `Snapshotter.run(outDir:)` (MenuApp.swift:50-89) writes: popover states (`running`, `idle-changes`, `paused`, `failed`, `first-run`, `dry-run`, `hover`, `drafts`, `flagged`, `too-large`, `update`, `updating`, `tend`) in light and dark, plus "open" variants; `menubar.png`; `index.html` (dashboard); `app/*.png` (window sections, approach call edit, split, onboarding steps, 960×640 minimum); `shortcuts-*.png`; `review-*.png` (landed, noresult, notposted).
- Window fixtures use `WindowFixtures.clock` (2026-10-21 16:19, WindowFixtures.swift:13) so renders match their mockups.
- `Store(snapshot:)` is a fixture store: never reads or writes disk, never runs checks, never touches launchd (Store.swift:228-255, `isFixture`).
- `Fixtures` (MenuApp.swift:317-500+) holds popover fixtures. `WindowFixtures` (App/WindowFixtures.swift:6-635) holds window and onboarding fixtures.
- Output of this path is documented in CONTRIBUTING.md:23 and RELEASING.md:11 (`docs/shots/*.png`, `docs/media/hero.gif`).

---

## 6. Tests

Test files in `Tests/GlidepathTests/` that touch UI or presentation code (type names from the test body):

| Test file | UI types used |
|---|---|
| ApproachGeometryTests.swift | `ApproachGeometry` (21), `Motion` |
| FlightRecorderTests.swift | `ApproachState`, `FlightText`, `ReviewRow` |
| HistoryTests.swift | `ReviewSweep`, `ReviewsModel` |
| ListNavTests.swift | `ListNav` (32 uses) |
| OnboardingTests.swift | `OnboardingSummary`, `Strip` |
| PreparingTests.swift | `Presentation`, `Snapshot` |
| PresentationTests.swift | `Presentation` (32), `Profile` (12), `PRRow`, `OnboardingSummary`, `Snapshot`, `Strip` |
| ReviewCommandTests.swift | `Presentation`, `PRRef` |
| ShortcutTests.swift | `ShortcutAction`, `ShortcutAvailability`, `ShortcutState`, `Shortcuts` |
| SplitBuilderTests.swift | `SplitBuilderModel`, `Store`, `WindowFixtures` (`section("approach")`) |
| StackCapTests.swift | `StackGeometry`, `Strip` |
| StateTests.swift | `Store` |
| WindowRouterTests.swift | `WindowRouter.opensOnboarding(...)` |

Core-only tests that do not touch the UI: the rest, including `ConfigTests`, `ScheduleTests`, `TendCoreTests`, `TendCLITests`, `TranscriptTests`, `UpdatesTests`, `LaunchdTests` and `SecurityTests`.

**Snapshot fixtures are not tested.** No test compares images. `WindowFixtures` and `Fixtures` are used by:

- `Snapshotter` (`glidepath --snapshot <dir>`), a manual render for visual review against the mockups. Outputs go to `docs/shots/` and are checked by eye (RELEASING.md:11).
- Tests that need a store without disk: `Store(snapshot: WindowFixtures.section(...))` (SplitBuilderTests.swift:10).

**CI** runs `swift test` on macos-latest (ci.yml:15). No snapshot step.

---

## 7. Dependency sketch: which UI files can go together

Core/CLI: a UI file can be deleted without touching Core, because Core never imports UI. The exceptions are in §4c: `Presentation.swift`, the `Snapshot` and `Strip` structs in `Store.swift`, and `HeaderCopy` in `Popover.swift`. Keep those (or move them to Core) before deleting anything nearby.

Clusters, with the UI files each one depends on (from the edge list of type references across App/Window/UI):

**A. Snapshot and render tooling** (safe to delete as one, with `main.swift` argv branches and `MenuApp.swift`'s `Snapshotter` and `Fixtures`)
- `App/HeroGIF.swift`, `App/WindowFixtures.swift`, and `Snapshotter`/`Fixtures` in `App/MenuApp.swift` (:49-502).
- Inbound: `Window/Controls.swift` names `WindowFixtures` (check the comment before cutting). Tests: `SplitBuilderTests.swift` uses `WindowFixtures.section`. Docs: CONTRIBUTING.md:23, RELEASING.md:11.
- Delete also breaks the `docs/shots/` regeneration.

**B. Settings section** (Settings.swift 957, SettingsModel.swift 564, SettingsLinear.swift 48, SettingsPlaybook.swift 159, QuietHoursField.swift 41)
- Inbound: `MainWindow.swift:70-72` (`SettingsView`). `Onboarding.swift` uses `FixInTerminal` from `SettingsModel.swift:495`, so move `FixInTerminal` and `ClaudeAccount` first. `SettingsParts.swift` controls are used by ApproachSection, BriefingCard, SplitBuilder and OnboardingFinish, so keep `SettingsParts.swift` (417 lines) unless those callers change.
- `Settings.swift` and `SettingsModel` also reference `NotifySound`, `Autopilot`, `Lessons` and other Core types only, so no Core change.

**C. Onboarding** (Onboarding.swift 993, OnboardingFinish.swift 437, HeroField.swift 82)
- Inbound: `MainWindow.swift:38-46` (`OnboardingView`) and `WindowRoot.swift` (`showOnboarding`, `needsSetup`). `WindowRouter` must keep working with no onboarding view: it still checks config.
- `OnboardingFinish.swift` `OnboardingSetup.run` (:408-437) does real install work. Move it into Core/CLI before the view goes, or the install path disappears with the UI.
- Uses `ScheduleControls.swift` (`DialEditor`, `ScheduleDialView`, `DayPills`), `RepoPicker.swift` (shared with Repos), `Controls.swift`, `Mark.swift` and `Sidebar.swift` (word matches; verify).

**D. Approach** (ApproachSection.swift 1201, ApproachChart.swift 395, BriefingCard.swift 81, SplitBuilder.swift 259)
- Inbound: `MainWindow.swift` (`ApproachSectionView`), `Popover.swift` (`ApproachPopoverBlock`, defined in ApproachSection.swift:293), `Now.swift` (`CallEditCard`, `CallEditModel`, `TendNeedRow`, all from ApproachSection.swift). `Popover.swift` also uses `StackGeometry`, which `ApproachSection` also uses (Popover.swift:28).
- So Approach is not standalone: removing it means editing Now.swift and Popover.swift. `ApproachProfile` in Profile.swift is also related.

**E. History and review sheet** (Reviews.swift 280, FlightRecorder.swift 1200, ReviewSheet.swift 302, RunCard.swift 293)
- Inbound: `MainWindow.swift` (`HistoryView`), `Now.swift` (`ReviewNowSheet`, `RunCard`, `ReviewsModel`, `RunsKey`), `MenuApp.swift` (`ReviewSheet` in Snapshotter). `Reviews.swift` uses `RunCard` and `FlightRecorder`'s `ReviewSheet`. `FlightRecorder.swift` uses `Avatar` and `WinButton` from `Controls.swift`.
- `Store.reviewText`, `allRuns`, and `draftPreview` are the store calls for this cluster.

**F. Repos** (Repos.swift 828, RepoPicker.swift 251)
- Inbound: `Now.swift` and `ReviewSheet.swift` use `ReposModel` and `AddRepoSheet`. Onboarding uses `RepoPicker`. Repos is not standalone.

**G. Schedule** (Schedule.swift 377, ScheduleControls.swift 576)
- Inbound: `MainWindow.swift` (`ScheduleView`), `AppDelegate.swift` (reads `ScheduleModel.live` for quit flush), `Onboarding.swift` (`DialEditor`), `OnboardingFinish.swift` (`DayPills`, `ScheduleDialView`). Keep `ScheduleModel.flushLive` for the quit path (AppDelegate.swift:17-26, MainWindowLifecycle).

**H. Popover and menu bar** (Popover.swift 797, Popover/Card.swift 374, MenuBarLabel.swift 244, Profile.swift 412, ListNav.swift 73, GlobalHotkey.swift 92)
- Inbound: `MenuApp.swift` (scenes), `AppDelegate.swift`, `Store.swift`. `Profile.swift` and `Presentation.swift` are used by the CLI or by Core (§4c). `Card.swift` depends on `Avatar`, `Glass`, `Tracer`, `HoldButton`.

**I. Shared, keep for any rebuild**
- `App/Store.swift` (Snapshot, Strip, Store), `App/Presentation.swift`, `App/Theme.swift`, `App/Shortcuts.swift`, `App/ShortcutCommands.swift`, `App/Confirms.swift`, `App/Notifier.swift`, `App/BriefingFile.swift`.
- `UI/*` (Avatar, Glass, Gotham, HoldButton, Motion, Tracer). Used across Window and Popover.
- `Window/Controls.swift`, `Window/Mark.swift`, `Window/WindowRoot.swift`, `Window/MainWindow.swift`, `Window/Sidebar.swift`, `Window/ShortcutsSheet.swift`, `Window/Now.swift` (Now is the main section, and Confirms and popover actions go through it).

**Summary of what can go together:** A (render tooling) is the only cluster with no inbound edges from the live app path except `Controls.swift`'s comment. Clusters B, C and E can go together if `FixInTerminal`, `OnboardingSetup.run` and the `SettingsParts` controls are moved first and `Now.swift`'s review-sheet entries are removed. D and F are coupled to Now and Popover, so they are not separable without editing those files.

---

## Open items found while mapping

- `Store.openDashboard`, `dryStrips`, `errorText`, `setHovered` and `reconcileJob` have no caller outside Store.swift (§3).
- `ApproachModel` (ApproachSection.swift:1143-1200) writes Playbook and TendStore from the view layer, which Core could own (§4b.6).
- `OnboardingSetup.run` (OnboardingFinish.swift:408-437) performs install work from a view file (§4b.7).
- `Shortcuts.swift` and `ShortcutCommands.swift` name Core types in a way the grep cannot prove are code rather than comments. Check before relying on that list.
