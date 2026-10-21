import Foundation

/// Reads token usage from Claude Code session transcripts.
/// Counted tokens are input + output + cache writes. Cache reads are left out: they are cheap and
/// would dominate the total on long sessions.
enum Transcript {
    struct Usage: Equatable {
        var total = 0
        var byPR: [Int: Int] = [:]
    }

    static func projectDir(paths: Paths, cwd: String) -> String {
        let encoded = String(cwd.map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" })
        return paths.claudeProjectsDir + "/" + encoded
    }

    /// Sums usage over distinct assistant messages. A streamed message is written as several lines
    /// with the same `message.id`, so each id counts once.
    static func tokens(lines: [String]) -> Int {
        var seen = Set<String>()
        var total = 0
        for line in lines {
            guard let obj = json(line), obj["type"] as? String == "assistant",
                  let message = obj["message"] as? [String: Any],
                  let usage = message["usage"] as? [String: Any] else { continue }
            let id = message["id"] as? String ?? UUID().uuidString
            guard seen.insert(id).inserted else { continue }
            total += int(usage["input_tokens"]) + int(usage["output_tokens"]) + int(usage["cache_creation_input_tokens"])
        }
        return total
    }

    /// The text of the first user message in a subagent transcript, which holds its brief.
    static func firstUserText(lines: [String]) -> String? {
        for line in lines {
            guard let obj = json(line), obj["type"] as? String == "user",
                  let message = obj["message"] as? [String: Any] else { continue }
            if let text = message["content"] as? String { return text }
            if let blocks = message["content"] as? [[String: Any]] {
                return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
        }
        return nil
    }

    /// PR numbers mentioned in a brief, e.g. "PR 42" or "reviews/42/".
    static func mentions(_ text: String) -> Set<Int> {
        var out = Set<Int>()
        var current = ""
        for ch in text + " " {
            if ch.isASCII && ch.isNumber {
                current.append(ch)
            } else {
                if let n = Int(current), current.count <= 6 { out.insert(n) }
                current = ""
            }
        }
        return out
    }

    /// Total for the main session plus its subagents. A subagent is attributed to a PR only when its
    /// brief names exactly one of the PRs this run is reviewing; everything else stays in the total.
    static func usage(paths: Paths, cwd: String, sessionId: String, keptPRs: Set<Int>) -> Usage {
        let dir = projectDir(paths: paths, cwd: cwd)
        let fm = FileManager.default
        var usage = Usage()
        let main = dir + "/" + sessionId + ".jsonl"
        if let lines = readLines(main) { usage.total += tokens(lines: lines) }

        let subDir = dir + "/" + sessionId + "/subagents"
        let files = ((try? fm.contentsOfDirectory(atPath: subDir)) ?? []).filter { $0.hasSuffix(".jsonl") }
        for file in files {
            guard let lines = readLines(subDir + "/" + file) else { continue }
            let count = tokens(lines: lines)
            usage.total += count
            let named = firstUserText(lines: lines).map { mentions($0).intersection(keptPRs) } ?? []
            if named.count == 1, let n = named.first {
                usage.byPR[n, default: 0] += count
            }
        }
        return usage
    }

    private static func readLines(_ path: String) -> [String]? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func json(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }
}
