import Foundation

// Fake, in-memory data only. Nothing here touches the network or ~/.config/glidepath.

enum Need: String {
    case post, push, reply, merge, revert, stuck, ping

    var label: String {
        switch self {
        case .post: "Review ready to post"
        case .push: "Fix ready to push"
        case .reply: "Reply ready"
        case .merge: "Ready to merge"
        case .revert: "Revert ready"
        case .stuck: "Stuck"
        case .ping: "Waiting on Gadi for 26 h"
        }
    }
    var button: String {
        switch self {
        case .post: "Post review"
        case .push: "Push fix"
        case .reply: "Send reply"
        case .merge: "Merge"
        case .revert: "Open revert PR"
        case .stuck: "Try again"
        case .ping: "Ping Gadi"
        }
    }
    var hint: String {
        switch self {
        case .post: "Hold to post"
        case .push: "Hold to push"
        case .reply: "Hold to send"
        case .merge: "Hold to merge"
        case .revert: "Hold to open"
        case .stuck: ""
        case .ping: "Hold to ping"
        }
    }
    /// Only what goes to GitHub as you is a hold. Try again stays on this Mac.
    var isHold: Bool { self != .stuck }
}

enum TeamState: String { case ready, reviewed, skipped, unchecked }
enum MineGroup: String, CaseIterable {
    case needsYou, onIt, waiting, ready, merged
    var title: String {
        switch self {
        case .needsYou: "Needs you"
        case .onIt: "Glidepath is on it"
        case .waiting: "Waiting on reviewers"
        case .ready: "Ready to merge"
        case .merged: "Merged this week"
        }
    }
}
enum Step: String { case done, todo, needs, running }
enum Severity: String { case mustFix = "Must fix", shouldFix = "Should fix", nit = "Nit" }

struct Finding: Hashable { var severity: Severity; var text: String; var file: String }
struct Moment: Hashable { var time: String; var text: String }

struct PR: Identifiable, Hashable {
    let id: String
    var repo: String
    var number: Int
    var title: String
    var author: String
    var mine = false
    var need: Need?
    var since = 0                 // order the Needs you list, oldest first
    var reason = ""               // one line: why it needs you / where it stands
    // Team PRs
    var state: TeamState = .unchecked
    var verdict = ""
    var review: [String] = []
    var findings: [Finding] = []
    var checked: [String] = []
    var log: [Moment] = []
    var skip = ""
    var lines = 0
    var files = 0
    // Your PRs
    var group: MineGroup = .onIt
    var steps: [Step] = [.todo, .todo, .todo, .todo]   // CI · Comments · Approval · Merge
    var timeline: [Moment] = []
    var ask = ""
    var reply = ""
    var fix = ""
    var ping = ""
    var lookAfter = true

    var ref: String { "\(repo) #\(number)" }
    var shortRef: String { "#\(number)" }
}

enum ActivityKind: String { case check, review, mine, skip, learn, problem, summary
    var symbol: String {
        switch self {
        case .check: "arrow.triangle.2.circlepath"
        case .review: "text.bubble"
        case .mine: "arrow.triangle.merge"
        case .skip: "forward"
        case .learn: "lightbulb"
        case .problem: "exclamationmark.triangle"
        case .summary: "moon.stars"
        }
    }
}

struct ActivityItem: Identifiable, Hashable {
    let id = UUID()
    var day: Int          // 0 today, -1 yesterday
    var time: String
    var kind: ActivityKind
    var text: String
    var pr: String?
    var fix: String?      // button title for problems
}

struct Learned: Identifiable, Hashable { let id = UUID(); var kind: String; var text: String }

enum Reviewers: String, CaseIterable { case everyone = "Everyone", collaborators = "Collaborators", these = "These people" }

struct Repo: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var review = true
    var lookAfter = true
    var last: String
    var who: Reviewers = .everyone
    var people: [String] = []
    var rules = ""
    var extend = true
    var learned: [Learned] = []
    var flags: [String] = []
}

enum Seed {
    static let prs: [PR] = [
        PR(id: "web-1276", repo: "lumen/web", number: 1276, title: "Selection race in the upload picker", author: "eleyy",
           need: .post, since: 1, reason: "Changes requested: the race is still open and there is no error state.",
           state: .ready, verdict: "Changes requested",
           review: ["Two things before this merges.",
                    "A second pick is accepted while the first upload is still resolving, so two files can claim one slot. Guarding `onPick` with the pending flag closes it.",
                    "When the upload fails the spinner keeps running. An error state with Try again would match the rest of the picker."],
           findings: [Finding(severity: .mustFix, text: "A second pick is accepted while the first upload is still resolving, so two files can claim one slot.", file: "src/upload/Picker.tsx:88"),
                      Finding(severity: .shouldFix, text: "A failed upload leaves the spinner running; there is no error state.", file: "src/upload/Picker.tsx:131"),
                      Finding(severity: .nit, text: "`pending` shadows the outer variable of the same name.", file: "src/upload/usePick.ts:24")],
           checked: ["Read 6 files, 214 lines changed", "Ran the picker tests: 41 passed", "Asked a second opinion on the race: it agreed"],
           log: [Moment(time: "1:02 PM", text: "Fetched the diff: 6 files, 214 lines"),
                 Moment(time: "1:02 PM", text: "Read the review rules in .glidepath/review.md"),
                 Moment(time: "1:03 PM", text: "Found 4 possible issues"),
                 Moment(time: "1:04 PM", text: "Checked each against the code: kept 3, dropped 1"),
                 Moment(time: "1:04 PM", text: "Asked a second opinion on the race: it agreed"),
                 Moment(time: "1:05 PM", text: "Wrote the review: changes requested")],
           lines: 214, files: 6),
        PR(id: "web-1277", repo: "lumen/web", number: 1277, title: "Fan-out publish for shared ids", author: "eleyy",
           reason: "Posted at 1:04 PM: changes requested.", state: .reviewed, verdict: "Changes requested",
           review: ["The fan-out keys on the id alone, so a second owner of the same id is dropped. Keying on (owner, id) fixes it."],
           findings: [Finding(severity: .mustFix, text: "A second owner of the same id is dropped from the fan-out.", file: "src/publish/fanout.ts:57")],
           checked: ["Read 4 files, 162 lines changed", "Ran the publish tests: 18 passed"], lines: 162, files: 4),
        PR(id: "web-1274", repo: "lumen/web", number: 1274, title: "Read-only endpoints for the asset list", author: "eleyy",
           reason: "Posted at 1:05 PM: approved.", state: .reviewed, verdict: "Approved",
           review: ["Looks good. Two edge cases worth a test: an empty folder and a folder you lost access to."],
           findings: [Finding(severity: .nit, text: "No test for a folder you lost access to.", file: "src/assets/list.test.ts")],
           checked: ["Read 9 files, 388 lines changed", "Ran the asset tests: 63 passed"], lines: 388, files: 9),
        PR(id: "web-1275", repo: "lumen/web", number: 1275, title: "Cross-discipline row adoption", author: "eleyy",
           reason: "Posted at 1:06 PM: changes requested.", state: .reviewed, verdict: "Changes requested",
           review: ["The adopted rows keep the legacy lock, so an edit in either discipline can overwrite the other."],
           findings: [Finding(severity: .mustFix, text: "Adopted rows keep the legacy lock id.", file: "src/rows/adopt.ts:112")],
           checked: ["Read 5 files, 241 lines changed"], lines: 241, files: 5),
        PR(id: "api-1288", repo: "lumen/api", number: 1288, title: "Cache org permissions per request in the audit log", author: "omar-h",
           reason: "Posted at 1:03 PM: approved.", state: .reviewed, verdict: "Approved",
           review: ["Clean. The cache lives for one request, so permissions cannot go stale."],
           checked: ["Read 3 files, 96 lines changed", "Ran the audit log specs: 27 passed"], lines: 96, files: 3),
        PR(id: "sager-412", repo: "SagerDrone/Sager", number: 412, title: "Battery telemetry ingest over MQTT", author: "nour-a",
           reason: "Skipped: 2,840 lines changed, over your 1,200 line limit.", state: .skipped,
           skip: "2,840 lines changed, over your 1,200 line limit.", lines: 2840, files: 31),
        PR(id: "sager-415", repo: "SagerDrone/Sager", number: 415, title: "Bump eslint to v10", author: "dependabot",
           reason: "Skipped: bot PRs are not reviewed.", state: .skipped, skip: "Bot PR. Bot PRs are not reviewed.", lines: 40, files: 2),
        PR(id: "api-1292", repo: "lumen/api", number: 1292, title: "Rate limits per org", author: "lina-m",
           reason: "Skipped: draft PRs are not reviewed.", state: .skipped, skip: "Draft PR. Draft PRs are not reviewed.", lines: 310, files: 7),
        PR(id: "web-1279", repo: "lumen/web", number: 1279, title: "Thumbnail cache eviction on low memory", author: "mina-k",
           reason: "Not checked yet. Next check at 5:00 PM.", state: .unchecked, verdict: "Changes requested",
           review: ["Eviction walks the cache oldest-first, which drops the thumbnails on screen before the ones scrolled away. Evicting by last-seen fixes it."],
           findings: [Finding(severity: .mustFix, text: "Visible thumbnails are evicted before off-screen ones.", file: "src/thumbs/cache.ts:40"),
                      Finding(severity: .nit, text: "The 0.8 threshold could be a named constant.", file: "src/thumbs/cache.ts:12")],
           checked: ["Read 3 files, 132 lines changed", "Ran the cache tests: 12 passed"], lines: 132, files: 3),
        PR(id: "web-1280", repo: "lumen/web", number: 1280, title: "Drag to reorder the upload queue", author: "eleyy",
           reason: "Not checked yet. Next check at 5:00 PM.", state: .unchecked, verdict: "Approved",
           review: ["Clean, and keyboard reorder works too. Nice touch on the drop indicator."],
           checked: ["Read 4 files, 178 lines changed", "Ran the queue tests: 22 passed"], lines: 178, files: 4),
        PR(id: "sager-418", repo: "SagerDrone/Sager", number: 418, title: "Snap waypoints to the grid in the mission planner", author: "rami-s",
           reason: "Not checked yet. Next check at 5:00 PM.", state: .unchecked, verdict: "Approved",
           review: ["Snapping happens in map units, so it holds up near the poles. Tests cover both."],
           findings: [Finding(severity: .nit, text: "`snapStep` could default from the zoom level.", file: "planner/snap.ts:19")],
           checked: ["Read 6 files, 264 lines changed", "Ran the planner tests: 54 passed"], lines: 264, files: 6),

        PR(id: "api-1253", repo: "lumen/api", number: 1253, title: "Export certifications as CSV", author: "yazan", mine: true,
           need: .push, since: 2, reason: "A date test failed on CI because it assumed UTC. Glidepath fixed it and the tests pass.",
           group: .needsYou, steps: [.needs, .done, .todo, .todo],
           timeline: [Moment(time: "1:09 PM", text: "Wrote a fix (a3f9c1) and ran the tests: 212 passed"),
                      Moment(time: "1:02 PM", text: "CI failed: export_spec expects UTC dates"),
                      Moment(time: "12:15 PM", text: "Replied to Omar and resolved the thread")],
           fix: "spec/exports/export_spec.rb\n- expect(row.issued_on).to eq(\"2026-10-26\")\n+ travel_to Time.zone.parse(\"2026-10-26 09:00 UTC\") do\n+   expect(row.issued_on).to eq(\"2026-10-26\")\n+ end"),
        PR(id: "api-1301", repo: "lumen/api", number: 1301, title: "Notification schema: migration and backfill", author: "yazan", mine: true,
           need: .merge, since: 3, reason: "Approved by Gadi. All 4 checks passed and the branch is up to date.",
           group: .needsYou, steps: [.done, .done, .done, .needs],
           timeline: [Moment(time: "1:12 PM", text: "Brought the branch up to date with main"),
                      Moment(time: "11:40 AM", text: "Gadi approved"),
                      Moment(time: "10:05 AM", text: "Answered Gadi on the backfill batch size")]),
        PR(id: "web-1250", repo: "lumen/web", number: 1250, title: "Keyboard focus in the upload picker", author: "yazan", mine: true,
           need: .reply, since: 4, reason: "Gadi asked whether the focus trap releases on Escape.",
           group: .needsYou, steps: [.done, .needs, .todo, .todo],
           timeline: [Moment(time: "2:01 PM", text: "Gadi asked whether the focus trap releases on Escape"),
                      Moment(time: "Yesterday", text: "Asked Gadi for a review")],
           ask: "Does the focus trap release on Escape? I couldn't tell from the diff.",
           reply: "Good catch. The trap releases on Escape; I added a test for it in 4e1d2b."),
        PR(id: "sager-409", repo: "SagerDrone/Sager", number: 409, title: "Undo in the geofence editor", author: "yazan", mine: true,
           reason: "Fixing CI: an e2e test times out on the slow runner.", group: .onIt, steps: [.running, .done, .done, .todo],
           timeline: [Moment(time: "2:08 PM", text: "Reproduced the e2e timeout locally"),
                      Moment(time: "1:40 PM", text: "CI failed: geofence.e2e timed out"),
                      Moment(time: "11:20 AM", text: "Rami approved")]),
        PR(id: "web-1262", repo: "lumen/web", number: 1262, title: "Paste images straight into comments", author: "yazan", mine: true,
           reason: "Waiting for Mina's review since this morning.", group: .waiting, steps: [.done, .done, .todo, .todo],
           timeline: [Moment(time: "9:30 AM", text: "Asked Mina for a review"), Moment(time: "9:12 AM", text: "CI passed")]),
        PR(id: "api-1310", repo: "lumen/api", number: 1310, title: "Generated client for the billing API", author: "yazan", mine: true,
           reason: "Fixing CI: lint fails in generated code.",
           group: .onIt, steps: [.running, .done, .todo, .todo],
           timeline: [Moment(time: "1:41 PM", text: "Second fix (c81e0a): lint still fails in src/gen/billing.ts"),
                      Moment(time: "1:30 PM", text: "First fix (77b2d4): lint still fails"),
                      Moment(time: "1:22 PM", text: "CI failed: lint, 3 errors in src/gen/billing.ts")]),
        PR(id: "api-1305", repo: "lumen/api", number: 1305, title: "Bulk archive for old certifications", author: "yazan", mine: true,
           reason: "Asked Gadi for a review yesterday at 12:10 PM. No reply yet.",
           group: .waiting, steps: [.done, .done, .todo, .todo],
           timeline: [Moment(time: "Yesterday", text: "Asked Gadi for a review"),
                      Moment(time: "Yesterday", text: "CI passed")],
           ping: "@gadi when you have a minute, this one is ready for another look. CI is green and the backfill question from #1301 is answered."),
        PR(id: "api-1246", repo: "lumen/api", number: 1246, title: "Retry webhook delivery with backoff", author: "yazan", mine: true,
           reason: "Merged today at 12:40 PM.", group: .merged, steps: [.done, .done, .done, .done],
           timeline: [Moment(time: "12:40 PM", text: "Merged"), Moment(time: "12:31 PM", text: "Brought the branch up to date with main")]),
        PR(id: "api-1240", repo: "lumen/api", number: 1240, title: "Audit log for certification changes", author: "yazan", mine: true,
           reason: "Merged yesterday at 4:40 PM.", group: .merged, steps: [.done, .done, .done, .done],
           timeline: [Moment(time: "Yesterday", text: "Merged")]),
    ]

    static let activity: [ActivityItem] = [
        ActivityItem(day: 0, time: "1:06 PM", kind: .review, text: "Posted a review: changes requested.", pr: "web-1275"),
        ActivityItem(day: 0, time: "1:05 PM", kind: .review, text: "Posted a review: approved.", pr: "web-1274"),
        ActivityItem(day: 0, time: "1:04 PM", kind: .review, text: "Posted a review: changes requested.", pr: "web-1277"),
        ActivityItem(day: 0, time: "1:03 PM", kind: .review, text: "Posted a review: approved.", pr: "api-1288"),
        ActivityItem(day: 0, time: "1:01 PM", kind: .skip, text: "Skipped: 2,840 lines changed, over the 1,200 line limit.", pr: "sager-412"),
        ActivityItem(day: 0, time: "1:01 PM", kind: .skip, text: "Skipped: bot PR.", pr: "sager-415"),
        ActivityItem(day: 0, time: "1:01 PM", kind: .skip, text: "Skipped: draft PR.", pr: "api-1292"),
        ActivityItem(day: 0, time: "1:00 PM", kind: .check, text: "Checked 3 repos: 9 PRs, 1 review ready to post, 3 skipped."),
        ActivityItem(day: 0, time: "12:40 PM", kind: .mine, text: "Merged.", pr: "api-1246"),
        ActivityItem(day: 0, time: "12:31 PM", kind: .learn, text: "Learned a rule for lumen/api: migrations need a down step."),
        ActivityItem(day: 0, time: "12:15 PM", kind: .mine, text: "Replied to Omar and resolved the thread.", pr: "api-1253"),
        ActivityItem(day: 0, time: "9:20 AM", kind: .problem, text: "Couldn't check SagerDrone/Sager at 9:00 AM: GitHub rate limit. Tried again at 9:20 AM and it worked.", fix: "Show log"),
        ActivityItem(day: 0, time: "8:00 AM", kind: .summary, text: "Overnight: 3 new team PRs, nothing needed you."),
        ActivityItem(day: -1, time: "5:02 PM", kind: .check, text: "Checked 3 repos: 4 reviews posted."),
        ActivityItem(day: -1, time: "4:40 PM", kind: .mine, text: "Merged.", pr: "api-1240"),
        ActivityItem(day: -1, time: "1:10 PM", kind: .review, text: "Posted a review on SagerDrone/Sager #407 Offline map tiles: approved."),
    ]

    static let repos: [Repo] = [
        Repo(name: "lumen/web", last: "Checked at 1:00 PM · 4 reviewed", who: .everyone, rules: ".glidepath/review.md",
             learned: [Learned(kind: "Command", text: "pnpm test --filter web"),
                       Learned(kind: "Rule", text: "Upload code must handle a failed upload with an error state")],
             flags: ["src/upload/**"]),
        Repo(name: "lumen/api", last: "Checked at 1:00 PM · 1 reviewed, 1 skipped", who: .collaborators, rules: ".glidepath/review.md",
             learned: [Learned(kind: "Rule", text: "Migrations need a down step"),
                       Learned(kind: "Command", text: "bin/rails test test/exports")],
             flags: ["db/migrations/**", ".github/workflows/**"]),
        Repo(name: "SagerDrone/Sager", last: "Checked at 1:00 PM · 2 skipped", who: .these, people: ["rami-s", "nour-a"],
             learned: [Learned(kind: "Command", text: "npm run test:e2e -- --project=chromium")],
             flags: ["firmware/**"]),
    ]
}
