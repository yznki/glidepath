import AppKit

/// The confirms every entry point shares: the popover, Overview, Reviews, the repo detail and the menus ask the same
/// questions, so a menu shortcut cannot skip one the buttons show.
@MainActor
enum Confirm {
    /// Runs a sweep, or one repo's review when `repo` is given. A run that posts reviews for real asks first: any repo
    /// on posting = "review" for a sweep, or that repo for a single-repo run.
    static func run(_ store: Store, repo slug: String? = nil) {
        let posts = slug.map { name in store.snap.config?.repos.first { $0.slug == name }?.posting == .review }
            ?? store.snap.postsReviews
        if posts {
            let asked = ask(slug.map { "Run the review pipeline for \($0) now?" } ?? "Run the review pipeline now?",
                            "Some repos post reviews with posting = \"review\", which show as real reviews on GitHub.",
                            confirm: "Run now", cancel: "Cancel")
            guard asked else { return }
        }
        store.runNow(repo: slug)
    }

    /// Stops the sweep, or the dry run.
    static func stop(_ store: Store) {
        let asked = ask(store.snap.dryRunning ? "Stop the dry run?" : "Stop the current sweep?",
                        "Reviews already posted stay posted.", confirm: "Stop", cancel: "Keep running")
        guard asked else { return }
        store.stopRun()
    }

    /// Discards a held draft. Cancel is the default and Esc; Discard is the destructive button.
    static func discard(_ strip: Strip, store: Store) {
        let asked = ask("Discard the draft review on \(strip.repo) #\(strip.number)?",
                        "The held review is deleted. Nothing is posted.",
                        confirm: "Discard", cancel: "Cancel", destructive: true, cancelIsDefault: true)
        guard asked else { return }
        store.discardDraft(strip)
    }

    /// Shows an alert and reports whether the confirm button was chosen.
    static func ask(_ message: String, _ info: String, confirm: String, cancel: String,
                    destructive: Bool = false, cancelIsDefault: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: cancel)
        if destructive { alert.buttons[0].hasDestructiveAction = true }
        if cancelIsDefault {
            // Cancel answers Esc, and Return too: it is the default button cell.
            alert.buttons[1].keyEquivalent = "\u{1b}"
            alert.window.defaultButtonCell = alert.buttons[1].cell as? NSButtonCell
        }
        return alert.runModal() == .alertFirstButtonReturn
    }
}
