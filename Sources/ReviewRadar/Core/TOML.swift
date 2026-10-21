import Foundation

enum TOMLValue: Equatable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])
}

struct TOMLError: Error, CustomStringConvertible, Equatable {
    var line: Int
    var message: String
    var description: String { "line \(line): \(message)" }
}

/// Reader for the TOML subset review-radar uses: `[table]` and `[[array.of.tables]]` headers
/// (dotted names allowed), bare or quoted keys, basic strings, integers, booleans, arrays
/// (may span lines) and `#` comments. Anything else is an error, so typos fail loudly.
enum TOML {
    static func parse(_ text: String) throws -> [String: TOMLValue] {
        // Swift treats "\r\n" as one Character, so normalize before the parser looks at characters.
        var normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if normalized.hasPrefix("\u{FEFF}") { normalized.removeFirst() }
        var parser = Parser(chars: Array(normalized))
        return try parser.document()
    }
}

private struct Parser {
    let chars: [Character]
    var i = 0
    var line = 1

    init(chars: [Character]) { self.chars = chars }

    var atEnd: Bool { i >= chars.count }

    func peek(_ offset: Int = 0) -> Character? {
        let j = i + offset
        return j < chars.count ? chars[j] : nil
    }

    func fail(_ message: String) -> TOMLError { TOMLError(line: line, message: message) }

    mutating func advance() {
        if chars[i] == "\n" { line += 1 }
        i += 1
    }

    mutating func skipSpaces() {
        while let c = peek(), c == " " || c == "\t" { i += 1 }
    }

    /// Spaces, tabs, newlines and comments.
    mutating func skipTrivia() {
        while let c = peek() {
            if c == "#" {
                while let d = peek(), d != "\n" { i += 1 }
            } else if c == " " || c == "\t" || c == "\r" || c == "\n" {
                advance()
            } else {
                break
            }
        }
    }

    /// Only spaces and an optional comment may follow a value or header on its line.
    mutating func expectLineEnd() throws {
        skipSpaces()
        if peek() == "#" {
            while let d = peek(), d != "\n" { i += 1 }
        }
        if atEnd { return }
        if peek() == "\r" { i += 1 }
        guard peek() == "\n" else { throw fail("unexpected text after value") }
        advance()
    }

    mutating func document() throws -> [String: TOMLValue] {
        var root: [String: TOMLValue] = [:]
        var header: [String] = []
        var defined = Set<String>()
        while true {
            skipTrivia()
            if atEnd { return root }
            do {
                if peek() == "[" {
                    let isArray = peek(1) == "["
                    i += isArray ? 2 : 1
                    skipSpaces()
                    let path = try parseDottedKey()
                    skipSpaces()
                    if isArray {
                        guard peek() == "]", peek(1) == "]" else { throw fail("expected ]]") }
                        i += 2
                        try appendTable(&root, path)
                    } else {
                        guard peek() == "]" else { throw fail("expected ]") }
                        i += 1
                        let name = path.joined(separator: ".")
                        guard defined.insert(name).inserted else { throw fail("table [\(name)] is defined twice") }
                        try modify(&root, path[...]) { _ in }
                    }
                    header = path
                    try expectLineEnd()
                } else {
                    let key = try parseKey()
                    skipSpaces()
                    guard peek() == "=" else { throw fail("expected = after key \(key)") }
                    i += 1
                    skipSpaces()
                    let value = try parseValue()
                    try expectLineEnd()
                    try modify(&root, header[...]) { table in
                        guard table[key] == nil else { throw TOMLError(line: 0, message: "key \(key) is defined twice") }
                        table[key] = value
                    }
                }
            } catch var error as TOMLError {
                error.line = line
                throw error
            }
        }
    }

    mutating func parseKey() throws -> String {
        if peek() == "\"" { return try parseString() }
        var s = ""
        while let c = peek(), c.isASCII, c.isLetter || c.isNumber || c == "_" || c == "-" {
            s.append(c)
            i += 1
        }
        guard !s.isEmpty else { throw fail("expected a key") }
        return s
    }

    mutating func parseDottedKey() throws -> [String] {
        var parts = [try parseKey()]
        skipSpaces()
        while peek() == "." {
            i += 1
            skipSpaces()
            parts.append(try parseKey())
            skipSpaces()
        }
        return parts
    }

    mutating func parseString() throws -> String {
        guard peek() == "\"" else { throw fail("expected a string") }
        if peek(1) == "\"" && peek(2) == "\"" { throw fail("multi-line strings are not supported") }
        i += 1
        var out = ""
        while true {
            guard let c = peek(), c != "\n" else { throw fail("unterminated string") }
            i += 1
            if c == "\"" { return out }
            guard c == "\\" else {
                out.append(c)
                continue
            }
            guard let e = peek() else { throw fail("unterminated string") }
            i += 1
            switch e {
            case "\"": out.append("\"")
            case "\\": out.append("\\")
            case "n": out.append("\n")
            case "t": out.append("\t")
            case "r": out.append("\r")
            default: throw fail("unsupported escape \\\(e)")
            }
        }
    }

    mutating func parseValue() throws -> TOMLValue {
        guard let c = peek() else { throw fail("expected a value") }
        if c == "\"" { return .string(try parseString()) }
        if c == "[" { return try parseArray() }
        if c == "-" || (c.isASCII && c.isNumber) {
            var s = ""
            if c == "-" {
                s.append(c)
                i += 1
            }
            while let d = peek(), d.isASCII, d.isNumber {
                s.append(d)
                i += 1
            }
            guard let n = Int(s) else { throw fail("invalid integer") }
            return .int(n)
        }
        if matches("true") {
            i += 4
            return .bool(true)
        }
        if matches("false") {
            i += 5
            return .bool(false)
        }
        throw fail("unsupported value")
    }

    mutating func parseArray() throws -> TOMLValue {
        i += 1
        var items: [TOMLValue] = []
        while true {
            skipTrivia()
            if peek() == "]" {
                i += 1
                return .array(items)
            }
            items.append(try parseValue())
            skipTrivia()
            if peek() == "," {
                i += 1
                continue
            }
            if peek() == "]" {
                i += 1
                return .array(items)
            }
            throw fail("expected , or ] in array")
        }
    }

    func matches(_ word: String) -> Bool {
        for (k, ch) in word.enumerated() where peek(k) != ch { return false }
        return true
    }

    /// Walks `path` from `table`, creating missing tables. An array of tables resolves to its
    /// last element, so keys after `[[repo]]` land in the newest repo.
    func modify(_ table: inout [String: TOMLValue], _ path: ArraySlice<String>,
                _ body: (inout [String: TOMLValue]) throws -> Void) throws {
        guard let head = path.first else {
            try body(&table)
            return
        }
        let rest = path.dropFirst()
        switch table[head] {
        case nil:
            var sub: [String: TOMLValue] = [:]
            try modify(&sub, rest, body)
            table[head] = .table(sub)
        case .table(var sub)?:
            table[head] = nil
            defer { table[head] = .table(sub) }
            try modify(&sub, rest, body)
        case .array(var items)?:
            guard !items.isEmpty, case .table(var last) = items.removeLast() else {
                throw TOMLError(line: 0, message: "\(head) is not a table")
            }
            table[head] = nil
            defer {
                items.append(.table(last))
                table[head] = .array(items)
            }
            try modify(&last, rest, body)
        default:
            throw TOMLError(line: 0, message: "\(head) is already a value, not a table")
        }
    }

    func appendTable(_ root: inout [String: TOMLValue], _ path: [String]) throws {
        guard let key = path.last else { throw TOMLError(line: 0, message: "empty table name") }
        try modify(&root, path.dropLast()[...]) { parent in
            switch parent[key] {
            case nil:
                parent[key] = .array([.table([:])])
            case .array(var items)?:
                items.append(.table([:]))
                parent[key] = .array(items)
            default:
                throw TOMLError(line: 0, message: "[[\(key)]] conflicts with an existing key")
            }
        }
    }
}
