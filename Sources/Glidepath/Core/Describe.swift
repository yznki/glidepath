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

    /// The body with the block in place of the marked span. Without a marked span, the block goes at the end.
    static func rewrite(_ body: String?, block: String) -> String {
        let text = body ?? ""
        if let start = text.range(of: open), let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
            return String(text[..<start.lowerBound]) + block + String(text[end.upperBound...])
        }
        return text.isEmpty ? block : text + "\n\n" + block
    }
}
