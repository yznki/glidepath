import Foundation

/// What a Needs-you item waits on. The associated values are what the row's words are built from.
enum NeedKind: Equatable {
    /// A review written and held, ready to post.
    case reviewReady(Verdict)
    /// A fix for the user's PR, committed and held, ready to push.
    case fixReady
    /// A reply to a reviewer, drafted and ready to send.
    case replyReady(to: String)
    /// A reviewer asked something Glidepath could not answer, and it wrote no reply.
    case question(from: String)
    case readyToMerge
    /// A PR Glidepath merged broke the default branch; a revert PR waits.
    case mainBroke(failing: [String])
    case splitProposed(parts: Int)
    case stuck
    case waitingOnReviewer(login: String, hours: Int)
    /// Skipped for size; the user may review it anyway.
    case tooLarge(lines: Int?)
}

/// The one thing a Needs-you row's button does.
enum NeedAction: Equatable {
    case post, push, reply, merge, revert, reviewSplit, retry, ping, reviewAnyway
}

/// One thing only the user can decide.
struct Need: Equatable, Identifiable {
    /// Stable across reloads: `owner/name#n/<part>`.
    let id: String
    let kind: NeedKind
    let repo: String
    let number: Int
    let title: String
    /// The PR's author. Nil for the user's own PRs.
    let author: String?
    /// The source's own words, when it has any: the fix summary, the reviewer's question, why it is stuck. Copy builds
    /// the row's line from this and the kind.
    let reason: String
    let action: NeedAction
    /// The action goes to GitHub as the user, so its button is a hold.
    let outward: Bool
    /// When it started waiting. Nil when the source does not say; those sort last.
    let since: Date?

    var prID: String { "\(repo)#\(number)" }
}

/// Everything that needs the user, from the review runs, the held drafts and tend's state. One list, one count: every
/// surface reads `derive` through the store, so the icon, popover, Dock and window always agree.
enum NeedsYou {
    /// Oldest first; items with no time keep their source order after those with one.
    static func derive(_ snap: Snapshot) -> [Need] {
        var out: [Need] = []
        let strips = Presentation.strips(from: snap.run)
        let started = snap.run?.started
        for s in strips where s.draft && s.verdict != nil {
            out.append(Need(id: s.id + "/review", kind: .reviewReady(s.verdict ?? .approve), repo: s.repo, number: s.number,
                            title: s.title ?? "", author: s.author, reason: "", action: .post, outward: true,
                            since: s.carriedFrom ?? started))
        }
        // The newest run's own size skips. A carried row was offered by the run it came from.
        for s in strips where s.skipReason == "size" && s.verdict == .skipped && s.carriedFrom == nil {
            out.append(Need(id: s.id + "/size", kind: .tooLarge(lines: s.changedLines), repo: s.repo, number: s.number,
                            title: s.title ?? "", author: s.author, reason: "", action: .reviewAnyway,
                            outward: reviewPosts(s.repo, snap.config), since: started))
        }
        for item in snap.approach?.needs ?? [] {
            out.append(need(item, snap))
        }
        return out.enumerated().sorted { a, b in
            switch (a.element.since, b.element.since) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.offset < b.offset
            }
        }.map(\.element)
    }

    /// One of tend's Needs items, read with the state behind it.
    static func need(_ item: NeedsItem, _ snap: Snapshot) -> Need {
        let key = "\(item.slug)#\(item.n)"
        func make(_ kind: NeedKind, _ action: NeedAction, outward: Bool, reason: String = "", since: Date? = nil) -> Need {
            Need(id: item.id, kind: kind, repo: item.slug, number: item.n, title: item.title, author: nil, reason: reason,
                 action: action, outward: outward, since: since)
        }
        switch item.kind {
        case "held":
            let held = snap.prStates[key]?.held
            return make(.fixReady, .push, outward: true, reason: held?.summary ?? item.detail, since: held?.at)
        case "call":
            let call = snap.calls[item.id]
            let who = call?.author ?? ""
            if call?.draft != nil {
                return make(.replyReady(to: who), .reply, outward: true, reason: call?.quote ?? "", since: call?.at)
            }
            return make(.question(from: who), .reply, outward: true, reason: call?.quote ?? "", since: call?.at)
        case "land":
            return make(.readyToMerge, .merge, outward: true)
        case "revert":
            let record = snap.landed.last { $0.slug == item.slug && $0.n == item.n }
            return make(.mainBroke(failing: record?.failing ?? []), .revert, outward: true, since: record?.at)
        case "split":
            let plan = snap.splits[key]
            return make(.splitProposed(parts: plan?.parts.count ?? 0), .reviewSplit, outward: false, since: plan?.at)
        case "blocked":
            // Tend writes the login into the id ("…/wait-<login>") and the hours into the detail ("Waiting 26 h on …").
            let login = item.id.components(separatedBy: "/wait-").last ?? ""
            let hours = Int(item.detail.split(separator: " ").dropFirst().first ?? "") ?? 0
            return make(.waitingOnReviewer(login: login, hours: hours), .ping, outward: true)
        default:
            // "stuck", and any kind a newer tend writes: the user looks, then tries again.
            return make(.stuck, .retry, outward: false, reason: item.detail)
        }
    }

    /// Whether a review run by hand on this repo posts to GitHub. A repo that holds reviews as drafts, or a dry-run
    /// config, posts nothing. With no config it is treated as posting, so the button stays a hold.
    static func reviewPosts(_ slug: String, _ config: Config?) -> Bool {
        guard let config else { return true }
        if config.dryRun { return false }
        return config.repos.first { $0.slug == slug }?.posting != .draft
    }
}
