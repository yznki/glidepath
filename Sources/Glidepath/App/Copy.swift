import Foundation

/// Every word the 2.0 app shows (docs/design/v2-ux/spec.md §3). New UI takes its words from here only, and a test keeps
/// the cut words out of this file. A GitHub draft PR is always "draft PR", never "draft".
enum Copy {
    // MARK: The words

    static let check = "Check"
    static let checkNow = "Check now"
    static let review = "Review"
    static let needsYou = "Needs you"
    static let readyToPost = "Ready to post"
    static let fixReady = "Fix ready"
    static let replyReady = "Reply ready"
    static let readyToMerge = "Ready to merge"
    static let stuck = "Stuck"
    static let skipped = "Skipped"
    static let askFirst = "Ask first"
    static let autopilot = "Autopilot"
    static let autopilotOn = "Autopilot on"
    static let pause = "Pause"
    static let resume = "Resume"
    static let stop = "Stop"
    static let undo = "Undo"
    static let open = "Open"
    static let quietHours = "Quiet hours"
    static let learned = "Learned"
    static let activity = "Activity"
    static let teamPRs = "Team PRs"
    static let yourPRs = "Your PRs"
    static let draftPR = "draft PR"
    static let sinceYouLastLooked = "Since you last looked"
    static let workingNow = "Working now"
    static let doneToday = "Done today"
    static let nothingNeedsYou = "Nothing needs you."
    static let lookAfterThisPR = "Look after this PR"
    /// The trust ramp's offers in the empty Inbox, one step at a time (spec §6a).
    static let offerLookAfterMyPRs = "Look after my PRs"
    static let offerAutopilot = "Turn on Autopilot"

    // MARK: Status

    /// The one sentence under every title: is it fine, and does it need me?
    static func status(_ state: GlideState, now: Date = Date(), calendar: Calendar = .current) -> String {
        switch state {
        case .quiet(let next):
            guard let next else { return "All good." }
            return "All good. Next check \(at(next, now: now, calendar: calendar))."
        case .checking(let p):
            if p.yourPRs { return "Working on your PRs…" }
            guard p.total > 0 else { return "Checking…" }
            let prs = p.total == 1 ? "1 PR" : "\(p.total) PRs"
            return p.repo.map { "Checking \(prs) in \($0)…" } ?? "Checking \(prs)…"
        case .needs(let count):
            return needsCount(count) + "."
        case .paused(let until):
            guard let until else { return "Paused." }
            return "Paused until \(when(until, now: now, calendar: calendar))."
        case .problem(let reason, _):
            switch reason {
            case .notSetUp: return "Pick the repos to check."
            case .notScheduled: return "Checks aren't scheduled."
            case .scheduleFailed(let error): return "Couldn't schedule checks: \(sentence(error))"
            case .signedOut: return "Can't reach GitHub: sign-in expired."
            case .checkFailed(let error): return "Last check failed: \(sentence(error))"
            }
        case .holdingBack(let reason, let resumes):
            let when = resumes.map { " Resumes \(at($0, now: now, calendar: calendar))." } ?? ""
            switch reason {
            case .usageReserve(let reserve):
                return "Holding back: \(reserve)% of your usage is kept for you.\(when)"
            case .quietHours:
                return "Waiting for quiet hours.\(when)"
            }
        }
    }

    /// The one control beside the status sentence.
    static func statusButton(_ state: GlideState) -> String {
        switch state {
        case .quiet: return checkNow
        case .checking: return stop
        case .needs: return open
        case .paused: return resume
        case .problem(_, let fix): return self.fix(fix)
        case .holdingBack: return "Adjust"
        }
    }

    static func fix(_ action: FixAction) -> String {
        switch action {
        case .setUp: return "Set up"
        case .installSchedule: return "Fix"
        case .signIn: return "Sign in"
        case .showLog: return "Show log"
        }
    }

    /// "1 thing needs you", "3 things need you". No full stop: headers add their own.
    static func needsCount(_ count: Int) -> String {
        count == 1 ? "1 thing needs you" : "\(count) things need you"
    }

    /// Under the popover's rows when more wait than it shows.
    static func more(_ count: Int) -> String { "and \(count) more" }

    // MARK: Needs you

    /// What the item needs, in amber on its row.
    static func label(_ kind: NeedKind) -> String {
        switch kind {
        case .reviewReady: return "Review ready to post"
        case .fixReady: return "Fix ready to push"
        case .replyReady: return replyReady
        case .question: return "Needs your answer"
        case .readyToMerge: return readyToMerge
        case .mainBroke: return "Revert ready"
        case .splitProposed: return "Split proposed"
        case .stuck: return stuck
        case .waitingOnReviewer(let login, let hours): return "Waiting on \(login) for \(hours) h"
        case .tooLarge: return "\(skipped): too large"
        }
    }

    /// The one line under the title that says why.
    static func reason(_ need: Need) -> String {
        switch need.kind {
        case .reviewReady(let verdict): return verdict == .changes ? "Asks for changes." : "Approves."
        case .fixReady: return need.reason.isEmpty ? "A fix for the failing check." : sentence(need.reason)
        case .replyReady(let who), .question(let who):
            guard !who.isEmpty else { return need.reason.isEmpty ? "A question on this PR waits on you." : sentence(need.reason) }
            return "\(who): \u{201C}\(need.reason)\u{201D}"
        case .readyToMerge: return "Approved, checks pass, no conflicts."
        case .mainBroke(let failing):
            guard !failing.isEmpty else { return "Main failed after it merged." }
            return "\(failing.joined(separator: ", ")) failed on main after it merged."
        case .splitProposed(let parts): return "Glidepath suggests \(parts) smaller PRs."
        case .stuck: return sentence(need.reason)
        case .waitingOnReviewer(let login, let hours): return "No review from \(login) in \(hours) working hours."
        case .tooLarge(let lines):
            return lines.map { "\($0.formatted()) lines, over your size limit." } ?? "Over your size limit."
        }
    }

    /// The row's one button, named for its result.
    static func button(_ need: Need) -> String {
        switch need.action {
        case .post: return "Post review"
        case .push: return "Push fix"
        case .reply: return "Send reply"
        case .merge: return "Merge"
        case .revert: return "Open revert PR"
        case .reviewSplit: return "Review split"
        case .retry: return "Try again"
        case .ping:
            if case .waitingOnReviewer(let login, _) = need.kind { return "Ping \(login)" }
            return "Ping"
        case .reviewAnyway: return "Review anyway"
        }
    }

    /// What a tap on a hold button says. Nil for actions that stay on this Mac.
    static func holdHint(_ need: Need) -> String? {
        guard need.outward else { return nil }
        switch need.action {
        case .post: return "Hold to post"
        case .push: return "Hold to push"
        case .reply: return "Hold to send"
        case .merge: return "Hold to merge"
        case .revert: return "Hold to open"
        case .ping: return "Hold to ping"
        case .reviewAnyway: return "Hold to review"
        case .reviewSplit, .retry: return nil
        }
    }

    // MARK: Since you last looked

    /// "Posted 3 reviews, pushed a fix to #1253, merged #1301". Empty when nothing happened.
    static func since(_ s: SinceLastLooked) -> String {
        var parts: [String] = []
        if s.reviewsPosted > 0 { parts.append(s.reviewsPosted == 1 ? "posted 1 review" : "posted \(s.reviewsPosted) reviews") }
        if !s.fixesPushed.isEmpty {
            parts.append((s.fixesPushed.count == 1 ? "pushed a fix to " : "pushed fixes to ") + numbers(s.fixesPushed))
        }
        if !s.merged.isEmpty { parts.append("merged " + numbers(s.merged)) }
        let text = parts.joined(separator: ", ")
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Helpers

    private static func numbers(_ ns: [Int]) -> String { ns.map { "#\($0)" }.joined(separator: ", ") }

    /// Text from elsewhere (an error, a summary) as a sentence: ends with one full stop.
    static func sentence(_ text: String) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = t.last else { return t }
        return ".!?…".contains(last) ? t : t + "."
    }

    /// "at 5:00 PM" today, "tomorrow at 9:00 AM", "Monday at 9:00 AM" within the week, "Nov 3 at 9:00 AM" after.
    static func at(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let day = dayWord(date, now: now, calendar: calendar)
        return (day.map { $0 + " at " } ?? "at ") + clock(date, calendar: calendar)
    }

    /// "9:00 AM" today, otherwise as `at`: "Paused until tomorrow at 9:00 AM".
    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let day = dayWord(date, now: now, calendar: calendar)
        return (day.map { $0 + " at " } ?? "") + clock(date, calendar: calendar)
    }

    private static func dayWord(_ date: Date, now: Date, calendar: Calendar) -> String? {
        if calendar.isDate(date, inSameDayAs: now) { return nil }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        var style = Date.FormatStyle(date: .omitted, time: .omitted)
        style.timeZone = calendar.timeZone
        if date > now, date.timeIntervalSince(now) < 6 * 86_400 { return date.formatted(style.weekday(.wide)) }
        return date.formatted(style.month(.abbreviated).day())
    }

    /// Locale time: 12 or 24 hour as the system has it.
    static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted)
        style.timeZone = calendar.timeZone
        return date.formatted(style.hour().minute())
    }
}
