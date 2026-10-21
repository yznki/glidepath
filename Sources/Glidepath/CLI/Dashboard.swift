import Foundation

/// `glidepath dashboard`: writes `<stateDir>/dashboard/index.html` from the last runs and the open drafts, then
/// opens it. The page has no script. Every string from GitHub or the model goes through `DashboardPage.esc`.
enum DashboardCommand {
    static let runLimit = 50

    static func main() -> Int32 {
        let paths = Paths()
        let runs = Array(RunStore(paths: paths).loadAll().sorted { $0.started > $1.started }.prefix(runLimit))
        let drafts = Drafts.all(paths)
        let now = Date()
        var snap = Snapshot()
        snap.run = runs.first
        snap.jobInstalled = FileManager.default.fileExists(atPath: paths.plistFile)
        snap.paused = Pause.isPaused(paths)
        snap.pausedSince = snap.paused ? Pause.since(paths) : nil
        if let config = try? Config.load(paths) {
            snap.nextRun = Store.nextSweep(schedule: config.schedule, days: config.days, after: now)
        }
        let header = HeaderCopy.make(Presentation.headerKind(snap, now: now), now: now, drafts: drafts.count)
        let html = DashboardPage.render(runs: runs, drafts: drafts, header: header, now: now)

        let dir = paths.stateDir + "/dashboard"
        let file = dir + "/index.html"
        do {
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: URL(fileURLWithPath: file), options: .atomic)
        } catch {
            eprint("could not write the dashboard: \(error.localizedDescription)")
            return 1
        }
        print(file)
        return Shell.inherit("/usr/bin/open", [file]) == 0 ? 0 : 1
    }
}

/// The page, as a string. Pure, so the snapshot tool and the tests render the same HTML.
enum DashboardPage {
    static let csp = "default-src 'none'; style-src 'unsafe-inline'; img-src data:"

    static func render(runs: [RunState], drafts: [Drafts.Found], header: HeaderCopy, now: Date) -> String {
        var out = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="\(csp)">
        <title>Glidepath dashboard</title>
        <style>
        \(css)
        </style>
        </head>
        <body>
        <main>
        <header>
        <h1>\(esc(header.headline))</h1>

        """
        if let line2 = header.line2 { out += "<p class=\"l2\">\(esc(line2))</p>\n" }
        if let line3 = header.line3 { out += "<p class=\"l3\">\(esc(line3))</p>\n" }
        out += "</header>\n"

        if !drafts.isEmpty {
            out += "<section>\n<h2>Drafts to post</h2>\n"
            for found in drafts {
                let d = found.draft
                let command = "glidepath drafts post \(d.slug) \(d.n)"
                out += "<article>\n<h3>\(prLink(d.slug, d.n)) <span class=\"verdict \(verdictClass(d.event))\">\(esc(eventLabel(d.event)))</span></h3>\n"
                out += "<p class=\"meta\">\(esc(stamp(d.created))) · post with <code>\(esc(command))</code></p>\n"
                out += "<pre>\(esc(d.body))</pre>\n"
                for c in d.comments {
                    out += "<p class=\"meta\">\(esc("\(c.path):\(c.line)")): \(esc(c.body))</p>\n"
                }
                out += "</article>\n"
            }
            out += "</section>\n"
        }

        out += "<section>\n<h2>Runs</h2>\n"
        if runs.isEmpty { out += "<p class=\"meta\">No runs yet.</p>\n" }
        for run in runs {
            out += runBlock(run)
        }
        out += "</section>\n</main>\n</body>\n</html>\n"
        return out
    }

    private static func runBlock(_ run: RunState) -> String {
        var head = "<h3>\(esc(stamp(run.started)))"
        var detail: [String] = []
        if let finished = run.finished {
            let minutes = Int(finished.timeIntervalSince(run.started) / 60)
            detail.append(minutes < 1 ? "under a minute" : "\(minutes) min")
        } else {
            detail.append("running")
        }
        if run.tokens > 0 { detail.append("\(compactTokens(run.tokens)) tokens") }
        head += " <span class=\"meta\">\(esc(detail.joined(separator: " · ")))</span></h3>\n"
        var out = "<article class=\"run\">\n" + head
        if let error = Presentation.failureMessage(run) {
            out += "<p class=\"error\">\(esc(error))</p>\n"
        }
        for repo in run.repos {
            out += "<h4>\(esc(repo.slug))</h4>\n"
            if let error = repo.error { out += "<p class=\"error\">\(esc(error))</p>\n" }
            if repo.prs.isEmpty { continue }
            out += "<ul class=\"rows\">\n"
            for pr in repo.prs {
                out += "<li>\n<div class=\"title\">\(esc(pr.title ?? "Untitled PR"))</div>\n"
                var meta = "\(prLink(repo.slug, pr.n)) · \(esc(pr.author ?? "unknown")) · "
                meta += "<span class=\"verdict \(verdictClass(pr.verdict))\">\(esc(verdictText(pr.verdict)))</span>"
                if pr.flagged == true { meta += " <span class=\"flag\">Flagged</span>" }
                if pr.draft == true { meta += " <span class=\"flag\">Draft to post</span>" }
                out += "<div class=\"meta\">\(meta)</div>\n"
                if let reason = pr.reason, !reason.isEmpty {
                    out += "<div class=\"reason\">\(esc(reason))</div>\n"
                }
                out += "</li>\n"
            }
            out += "</ul>\n"
        }
        return out + "</article>\n"
    }

    /// `&`, `<`, `>`, `"` and `'` as entities. Every string placed in the page passes through here.
    /// Walks unicode scalars, not Characters: `"` followed by a combining mark is one Character that is not `"`.
    static func esc(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    private static func prLink(_ slug: String, _ n: Int) -> String {
        "<a href=\"\(esc("https://github.com/\(slug)/pull/\(n)"))\">\(esc(slug)) #\(n)</a>"
    }

    private static func stamp(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    static func verdictText(_ verdict: Verdict?) -> String {
        switch verdict {
        case .approve?: return "● Approved"
        case .changes?: return "▲ Changes"
        case .skipped?: return "– Skipped"
        case nil: return "○ No result"
        }
    }

    private static func verdictClass(_ verdict: Verdict?) -> String {
        switch verdict {
        case .approve?: return "approve"
        case .changes?: return "changes"
        case .skipped?, nil: return "skip"
        }
    }

    private static func eventLabel(_ event: String) -> String {
        switch event {
        case "APPROVE": return "● Approve"
        case "REQUEST_CHANGES": return "▲ Request changes"
        default: return "Comment"
        }
    }

    private static func verdictClass(_ event: String) -> String {
        switch event {
        case "APPROVE": return "approve"
        case "REQUEST_CHANGES": return "changes"
        default: return "skip"
        }
    }

    static let css = """
    :root { color-scheme: light dark; }
    body { margin: 0; background: #F5F5F5; color: #111111;
      font: 14px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
    main { max-width: 760px; margin: 0 auto; padding: 32px 24px 48px; text-align: left; }
    h1 { font-size: 22px; font-weight: 600; margin: 0 0 6px; }
    h2 { font-size: 15px; font-weight: 600; margin: 36px 0 8px; padding-top: 16px; border-top: 1px solid rgba(17,17,17,0.08); }
    h3 { font-size: 14px; font-weight: 600; margin: 18px 0 4px; }
    h4 { font-size: 12px; font-weight: 600; color: #5C5C5C; margin: 16px 0 4px; }
    .l2 { margin: 0; }
    .l3 { margin: 0; color: #6B6B6B; font-size: 12px; }
    .meta { color: #5C5C5C; font-size: 12px; margin: 0; }
    .title { font-weight: 500; }
    .reason { color: #8A5300; font-size: 12px; margin-top: 2px; }
    .error { color: #C4242A; font-size: 12px; margin: 4px 0; }
    .flag { color: #5C5C5C; font-size: 11px; font-weight: 500; }
    .verdict.approve { color: #1B6B3F; }
    .verdict.changes { color: #8A5300; }
    .verdict.skip { color: #6B6B6B; }
    ul.rows { list-style: none; margin: 0; padding: 0; }
    ul.rows li { padding: 8px 0; border-top: 1px solid rgba(17,17,17,0.08); }
    article { margin-bottom: 8px; }
    pre { white-space: pre-wrap; word-wrap: break-word; margin: 8px 0; padding: 0 0 0 12px;
      border-left: 2px solid rgba(17,17,17,0.12); font: 13px/1.5 ui-monospace, Menlo, monospace; }
    code { font: 12px ui-monospace, Menlo, monospace; }
    a { color: #0060CC; text-decoration: none; }
    a:hover { text-decoration: underline; }
    @media (prefers-color-scheme: dark) {
      body { background: #222222; color: #F2F2F2; }
      h2 { border-top-color: rgba(242,242,242,0.10); }
      h4, .meta, .flag { color: #A8A8A8; }
      .l3 { color: #8E8E8E; }
      .reason { color: #FFC966; }
      .error { color: #FF6B6B; }
      .verdict.approve { color: #7EE0A6; }
      .verdict.changes { color: #FFC966; }
      .verdict.skip { color: #9A9A9A; }
      ul.rows li { border-top-color: rgba(242,242,242,0.10); }
      pre { border-left-color: rgba(242,242,242,0.2); }
      a { color: #4DA3FF; }
    }
    """
}
