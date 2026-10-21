import Foundation

/// PreToolUse guard for Bash inside review sessions. The command must be the glidepath binary followed by
/// plain tokens: bare words from a fixed ASCII set, or single-quoted strings. Anything else is denied, because
/// the shell (zsh) would expand it: `=(cmd)`, `*(e:...)`, `$(...)`, `{a,b}`, `~`, globs, `!`, `#`, `\`, and so on.
///
/// Everything is decided on UTF-8 bytes, never on Swift Characters. A Character can combine a quote with a
/// combining mark (`'` followed by U+0301 is one Character), so Character-level checks can be fooled. Non-ASCII
/// bytes and control bytes are refused before anything else, so no byte the shell might read differently
/// reaches the tokenizer.
///
/// Exit codes follow Claude Code's hook contract: 2 blocks the call and sends stderr to the model, 0 means no
/// decision (the normal allowlist applies). Any error exits 2, so the guard fails closed.
enum BashGuard {
    static let prefixText = "glidepath "

    private static let space: UInt8 = 0x20
    private static let quote: UInt8 = 0x27
    private static let bareExtras: Set<UInt8> = Set("_./:,@+-".utf8)

    /// Bytes allowed in a bare word: ASCII letters, digits, and `_./:,@+-`. Nothing the shell expands is in this set.
    static func isBareByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || bareExtras.contains(b)
    }

    struct Refusal: Error, Equatable {
        let reason: String
    }

    struct Token: Equatable {
        let text: String
        let quoted: Bool
    }

    /// Tokenizes the bytes after the prefix. Every comparison is on a byte.
    static func tokens(_ bytes: ArraySlice<UInt8>) -> Result<[Token], Refusal> {
        var out: [Token] = []
        var i = bytes.startIndex
        while i < bytes.endIndex {
            let b = bytes[i]
            if b == space {
                i += 1
                continue
            }
            if b == quote {
                let open = i + 1
                guard let close = bytes[open...].firstIndex(of: quote) else {
                    return .failure(Refusal(reason: "unterminated single quote"))
                }
                let after = close + 1
                if after < bytes.endIndex, bytes[after] != space {
                    return .failure(Refusal(reason: "a quoted word must be followed by a space"))
                }
                out.append(Token(text: String(decoding: bytes[open..<close], as: UTF8.self), quoted: true))
                i = after
                continue
            }
            var j = i
            while j < bytes.endIndex, isBareByte(bytes[j]) { j += 1 }
            if j == i {
                return .failure(Refusal(reason: "the character \(String(decoding: [b], as: UTF8.self).debugDescription) is not allowed in review commands"))
            }
            if j < bytes.endIndex, bytes[j] != space {
                return .failure(Refusal(reason: "the character \(String(decoding: [bytes[j]], as: UTF8.self).debugDescription) is not allowed in review commands"))
            }
            out.append(Token(text: String(decoding: bytes[i..<j], as: UTF8.self), quoted: false))
            i = j
        }
        return .success(out)
    }

    /// nil when the command may run, otherwise the reason it is denied.
    static func denial(for command: String) -> String? {
        let bytes = Array(command.utf8)
        // First, before any tokenizing: no non-ASCII byte anywhere (inside quotes too), no control bytes.
        if bytes.contains(where: { $0 >= 0x80 || $0 < 0x20 || $0 == 0x7F }) {
            return "non-ASCII and control characters are not allowed in review commands"
        }
        let prefix = Array(prefixText.utf8)
        guard bytes.starts(with: prefix) else {
            return "only glidepath subcommands may run in a review"
        }
        switch tokens(bytes[prefix.count...]) {
        case .failure(let refusal):
            return "\(refusal.reason) (review commands take plain words and single-quoted strings only)"
        case .success(let list):
            // Drafts are posted by the user from the app or a terminal. A review session never posts a held draft,
            // whatever the quoting.
            switch list.first?.text {
            case "drafts"?:
                return "glidepath drafts is for the user, not for a review; the draft waits for them to post it"
            case "review"?:
                return "glidepath review starts a review run; it is for the user, not for a review session"
            case "dashboard"?:
                return "glidepath dashboard writes a page and opens a browser; it is for the user, not for a review session"
            default:
                break
            }
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

    /// The keys whose repetition would let two JSON readers disagree about the command.
    static let singletonKeys = ["\"command\"", "\"tool_name\"", "\"tool_input\""]

    /// How many times `needle` occurs in `haystack`, byte for byte.
    static func occurrences(of needle: [UInt8], in haystack: [UInt8]) -> Int {
        guard !needle.isEmpty, haystack.count >= needle.count else { return 0 }
        var count = 0
        for start in 0...(haystack.count - needle.count) where haystack[start..<start + needle.count].elementsEqual(needle) {
            count += 1
        }
        return count
    }

    /// Decides from the hook's JSON input on stdin.
    static func evaluate(stdin: Data) -> (code: Int32, message: String?) {
        let raw = [UInt8](stdin)
        // A \u escape can spell a key (\u0063ommand is "command") and so hide a duplicate from the byte count
        // below. A legal command has no non-ASCII or control characters, so no legitimate input needs one.
        if occurrences(of: [0x5C, 0x75], in: raw) > 0 {
            return (2, "glidepath guard: a \\u escape is not allowed in hook input; blocked")
        }
        // Duplicate keys: a second "command" or "tool_name" could be read differently by another JSON parser.
        for key in singletonKeys where occurrences(of: Array(key.utf8), in: raw) > 1 {
            return (2, "glidepath guard: \(key) appears more than once in hook input; blocked")
        }
        guard let obj = (try? JSONSerialization.jsonObject(with: stdin)) as? [String: Any] else {
            return (2, "glidepath guard: unreadable hook input; blocked")
        }
        guard obj["tool_name"] as? String == "Bash" else { return (0, nil) }
        guard let input = obj["tool_input"] as? [String: Any], let command = input["command"] as? String else {
            return (2, "glidepath guard: no Bash command in hook input; blocked")
        }
        if let reason = denial(for: command) {
            return (2, "glidepath guard denied this command: \(reason)")
        }
        return (0, nil)
    }
}
