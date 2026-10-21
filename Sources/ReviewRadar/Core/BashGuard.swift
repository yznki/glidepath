import Foundation

/// PreToolUse guard for Bash inside review sessions. The command must be the review-radar binary
/// followed by plain tokens: bare words from a fixed character set, or single-quoted strings. Anything
/// else is denied, because the shell (zsh) would expand it: `=(cmd)`, `*(e:...)`, `$(...)`, `{a,b}`,
/// `~`, globs, `!`, `#`, `\`, and so on. Inside single quotes the shell expands nothing.
///
/// Exit codes follow Claude Code's hook contract: 2 blocks the call and sends stderr to the model,
/// 0 means no decision (the normal allowlist applies). Any error exits 2, so the guard fails closed.
enum BashGuard {
    static let prefix = "review-radar "

    /// Characters allowed in a bare word. Nothing the shell expands is in this set.
    static func isBare(_ c: Character) -> Bool {
        (c.isASCII && (c.isLetter || c.isNumber)) || "_./:,@+-".contains(c)
    }

    struct Refusal: Error, Equatable {
        let reason: String
    }

    struct Token: Equatable {
        let text: String
        let quoted: Bool
    }

    /// Splits the arguments after the prefix into tokens, or returns the reason it cannot.
    static func tokens(_ rest: Substring) -> Result<[Token], Refusal> {
        var out: [Token] = []
        var i = rest.startIndex
        while i < rest.endIndex {
            let c = rest[i]
            if c == " " {
                i = rest.index(after: i)
                continue
            }
            if c == "'" {
                let open = rest.index(after: i)
                guard let close = rest[open...].firstIndex(of: "'") else {
                    return .failure(Refusal(reason: "unterminated single quote"))
                }
                let after = rest.index(after: close)
                if after < rest.endIndex, rest[after] != " " {
                    return .failure(Refusal(reason: "a quoted word must be followed by a space"))
                }
                out.append(Token(text: String(rest[open..<close]), quoted: true))
                i = after
                continue
            }
            var j = i
            while j < rest.endIndex, isBare(rest[j]) { j = rest.index(after: j) }
            if j == i {
                return .failure(Refusal(reason: "the character \(String(c).debugDescription) is not allowed in review commands"))
            }
            if j < rest.endIndex, rest[j] != " " {
                return .failure(Refusal(reason: "the character \(String(rest[j]).debugDescription) is not allowed in review commands"))
            }
            out.append(Token(text: String(rest[i..<j]), quoted: false))
            i = j
        }
        return .success(out)
    }

    /// nil when the command may run, otherwise the reason it is denied.
    static func denial(for command: String) -> String? {
        guard command.hasPrefix(prefix) else {
            return "only review-radar subcommands may run in a review"
        }
        if command.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) {
            return "newlines and tabs are not allowed in review commands"
        }
        let rest = command.dropFirst(prefix.count)
        switch tokens(rest) {
        case .failure(let refusal):
            return "\(refusal.reason) (review commands take plain words and single-quoted strings only)"
        case .success(let list):
            // A value that starts with -- must be quoted, so a flag cannot be smuggled in as a value.
            for (index, token) in list.enumerated() where index > 0 {
                let previous = list[index - 1]
                if previous.text.hasPrefix("--"), !previous.quoted, !token.quoted, token.text.hasPrefix("--") {
                    return "a value starting with -- must be single-quoted"
                }
            }
            return nil
        }
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
