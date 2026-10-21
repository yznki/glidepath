import Foundation

/// PreToolUse guard for Bash inside review sessions. The allowlist already limits Bash to
/// `review-radar` subcommands; this adds a check on the command text itself, so that a
/// subcommand cannot be chained, substituted, redirected or grouped with anything else.
///
/// Exit codes follow Claude Code's hook contract: 2 blocks the call and sends stderr to the model,
/// 0 means no decision (the normal allowlist applies). Any error exits 2, so the guard fails closed.
enum BashGuard {
    static let prefix = "review-radar "

    /// Characters that chain, substitute or redirect commands. Newlines are included. Parentheses are
    /// allowed: without `$`, `<` or `>` in front of them they cannot form a subshell or process substitution.
    static let forbidden: Set<Character> = [";", "&", "|", "$", "`", ">", "<", "\n", "\r"]

    /// nil when the command may run, otherwise the reason it is denied.
    static func denial(for command: String) -> String? {
        guard command.hasPrefix(prefix) else {
            return "only review-radar subcommands may run in a review"
        }
        if let bad = command.first(where: { forbidden.contains($0) }) {
            return "the character \(bad.debugDescription) is not allowed in review commands"
        }
        return nil
    }

    /// Decides from the hook's JSON input on stdin.
    static func evaluate(stdin: Data) -> (code: Int32, message: String?) {
        guard let obj = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any] else {
            return (2, "review-radar guard: unreadable hook input; blocked")
        }
        guard obj["tool_name"] as? String == "Bash" else { return (0, nil) }
        guard let input = obj["tool_input"] as? [String: Any], let command = input["command"] as? String else {
            return (2, "review-radar guard: no Bash command in hook input; blocked")
        }
        if let reason = denial(for: command) {
            return (2, "review-radar guard denied this command: \(reason)")
        }
        return (0, nil)
    }
}
