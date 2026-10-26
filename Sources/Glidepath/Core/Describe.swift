import Foundation

/// The Glidepath block in a PR description: what changed since review, and the test plan. Only the text between the
/// markers is ever written.
enum Describe {
    static let open = "<!-- glidepath -->"
    static let close = "<!-- /glidepath -->"
    static let changeLimit = 10

    /// The changes with `line` added, keeping only the newest `changeLimit`.
    static func adding(_ line: String, to changes: [String]) -> [String] {
        Array((changes + [line]).suffix(changeLimit))
    }

    static func block(lines: [String], checks: [String]) -> String {
        var out = open + "\n### Changes since review\n" + lines.map { "- \($0)\n" }.joined()
        if !checks.isEmpty {
            out += "\n### Test plan\n" + checks.map { "- [x] `\($0)`\n" }.joined()
        }
        return out + close
    }

    /// The body with the block in place of the marked span. No markers: the block goes at the end. Exactly one open
    /// marker followed by exactly one close marker: the span between them is replaced. Anything else (a lone marker,
    /// repeated markers, a close before its open) is nil, and the caller leaves the body alone.
    static func rewrite(_ body: String?, block: String) -> String? {
        let text = body ?? ""
        let opens = occurrences(of: open, in: text)
        let closes = occurrences(of: close, in: text)
        if opens.isEmpty && closes.isEmpty {
            return text.isEmpty ? block : text + "\n\n" + block
        }
        guard opens.count == 1, closes.count == 1, let start = opens.first, let end = closes.first,
              start.upperBound <= end.lowerBound else { return nil }
        return String(text[..<start.lowerBound]) + block + String(text[end.upperBound...])
    }

    private static func occurrences(of marker: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var from = text.startIndex
        while let r = text.range(of: marker, range: from..<text.endIndex) {
            found.append(r)
            from = r.upperBound
        }
        return found
    }
}
