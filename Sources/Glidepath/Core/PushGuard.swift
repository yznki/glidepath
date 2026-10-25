import Foundation

/// One file in a change, as `git diff -U0` shows it.
struct ChangedFile: Equatable {
    var path: String
    /// "A" added, "D" deleted, "M" modified.
    var status: String
    /// The added lines, without the leading "+".
    var added: [String]
    /// How many lines were removed.
    var removed: Int
}

/// Checks a fix's diff before it is pushed. Pure: the caller reads the diff.
enum PushGuard {
    /// Parses `git diff --cached -U0 --no-color --no-renames`. Header lines are only read before a hunk, so a removed
    /// line that starts with "--" still counts. A file's path comes from its `+++ b/` line, or its `--- a/` line when
    /// it is deleted. The `diff --git` header is only the fallback, for a change with no such lines (a binary file).
    static func parse(diff: String) -> [ChangedFile] {
        var files: [ChangedFile] = []
        var inHunk = false
        for line in diff.components(separatedBy: "\n") {
            if line.hasPrefix("diff --git ") {
                // Fallback path: what follows the last " b/".
                let path = line.range(of: " b/", options: .backwards).map { String(line[$0.upperBound...]) } ?? line
                files.append(ChangedFile(path: path, status: "M", added: [], removed: 0))
                inHunk = false
                continue
            }
            guard !files.isEmpty else { continue }
            let last = files.count - 1
            if line.hasPrefix("@@") {
                inHunk = true
            } else if !inHunk && line.hasPrefix("--- a/") {
                files[last].path = headerPath(line, prefix: "--- a/")
            } else if !inHunk && line.hasPrefix("+++ b/") {
                files[last].path = headerPath(line, prefix: "+++ b/")
            } else if inHunk && line.hasPrefix("+") {
                files[last].added.append(String(line.dropFirst()))
            } else if inHunk && line.hasPrefix("-") {
                files[last].removed += 1
            } else if line.hasPrefix("new file mode") {
                files[last].status = "A"
            } else if line.hasPrefix("deleted file mode") {
                files[last].status = "D"
            }
        }
        return files
    }

    /// Why the change must not be pushed, or nil when it may. The first check that fails gives the reason.
    static func refusal(_ files: [ChangedFile], maxLines: Int) -> String? {
        guard !files.isEmpty else { return "Empty change" }
        if let file = files.first(where: { $0.path.hasPrefix(".github/") || $0.path.contains("/.github/") || isSecret($0.path) }) {
            return "Touches \(file.path)"
        }
        if let file = files.first(where: { $0.status == "D" && isTestPath($0.path) }) {
            return "Deletes test file \(file.path)"
        }
        if let file = files.first(where: { $0.added.contains(where: skipsTest) }) {
            return "Skips a test in \(file.path)"
        }
        let total = files.reduce(0) { $0 + $1.added.count + $1.removed }
        if maxLines > 0 && total > maxLines { return "\(total) changed lines, over max_fix_lines \(maxLines)" }
        return nil
    }

    /// The path after a `---`/`+++` prefix. Git adds a tab after a name with a space in it, which is not part of the name.
    private static func headerPath(_ line: String, prefix: String) -> String {
        var path = String(line.dropFirst(prefix.count))
        if path.hasSuffix("\t") { path.removeLast() }
        return path
    }

    /// A test by its folder (test, tests, __tests__, spec) or its name (*.test.*, *.spec.*, *_test.*, test_*.py, *Tests.swift).
    static func isTestPath(_ path: String) -> Bool {
        let parts = path.components(separatedBy: "/")
        let name = parts.last ?? path
        if parts.dropLast().contains(where: { ["test", "tests", "__tests__", "spec"].contains($0) }) { return true }
        return name.contains(".test.") || name.contains(".spec.") || name.contains("_test.")
            || (name.hasPrefix("test_") && name.hasSuffix(".py")) || name.hasSuffix("Tests.swift")
    }

    private static func isSecret(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        return name.contains(".env") || name.hasSuffix(".pem") || name.hasSuffix(".key")
    }

    /// Skip markers in the frameworks glidepath sees. `xit(` must not start a longer name such as `exit(`.
    private static let skipPattern = #"(?<![A-Za-z0-9_])(xit|xdescribe|it\.todo|t\.Skip)\(|\.skip\(|@pytest\.mark\.skip"#

    private static func skipsTest(_ line: String) -> Bool {
        line.range(of: skipPattern, options: .regularExpression) != nil
    }
}
