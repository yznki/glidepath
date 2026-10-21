import Foundation

/// The latest release, as the releases endpoint reports it.
struct Release: Equatable {
    let version: String
    let url: String
    let notes: String
}

/// `<stateDir>/update.json`: the last successful check. The app and `glidepath update` both read it.
struct UpdateCache: Codable, Equatable {
    var checked: Date
    var latest: String
    var url: String
}

/// How this binary was installed. A Homebrew install updates through brew; a source build is updated by hand.
enum InstallKind: Equatable {
    case homebrew(prefix: String)
    case source

    /// The binary's symlinks are resolved first, so a `/opt/homebrew/bin/glidepath` link counts as its Cellar keg.
    static func of(binary: String) -> InstallKind {
        let path = URL(fileURLWithPath: binary).resolvingSymlinksInPath().path
        guard let range = path.range(of: "/Cellar/glidepath/") else { return .source }
        return .homebrew(prefix: String(path[..<range.lowerBound]))
    }

    /// Where the menu bar app link points. Homebrew repoints `opt/glidepath` on each upgrade; a keg path does not survive one.
    static func appTarget(binary: String, app: String) -> String {
        if case .homebrew(let prefix) = of(binary: binary) { return prefix + "/opt/glidepath/Glidepath.app" }
        return app
    }
}

enum Updates {
    static let endpoint = "https://api.github.com/repos/yznki/glidepath/releases/latest"
    /// Automatic checks: at launch when the cache is this old, then on the same interval while running.
    static let maxAge: TimeInterval = 24 * 3600
    /// The popover checks when the cache is older than this.
    static let popoverMaxAge: TimeInterval = 6 * 3600

    /// "1.0.3" or "v1.0.3" as [1, 0, 3]. Anything else is nil.
    static func semver(_ text: String) -> [Int]? {
        let trimmed = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        return numbers
    }

    /// False when either side is not a version: bad input means no update.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let a = semver(latest), let b = semver(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    static func isDue(_ cache: UpdateCache?, now: Date, maxAge: TimeInterval) -> Bool {
        guard let cache else { return true }
        return now.timeIntervalSince(cache.checked) > maxAge
    }

    static func parseRelease(_ data: Data) -> Release? {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = root["tag_name"] as? String, semver(tag) != nil,
              let url = root["html_url"] as? String else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, url: url, notes: root["body"] as? String ?? "")
    }

    /// One unauthenticated GET. Blocks until GitHub answers or 15 s pass, so call it off the main thread.
    static func fetchLatest() throws -> Release {
        var request = URLRequest(url: URL(string: endpoint)!, timeoutInterval: 10)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        final class Box: @unchecked Sendable { var result: Result<Data, Error> = .failure(StateError("no answer")) }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.result = .failure(error)
            } else if let http = response as? HTTPURLResponse, http.statusCode == 200, let data {
                box.result = .success(data)
            } else {
                box.result = .failure(StateError("GitHub answered \((response as? HTTPURLResponse)?.statusCode ?? 0)"))
            }
            done.signal()
        }.resume()
        guard done.wait(timeout: .now() + 15) == .success else { throw StateError("no answer from GitHub") }
        guard let release = parseRelease(try box.result.get()) else { throw StateError("unexpected reply from GitHub") }
        return release
    }

    static func cached(_ paths: Paths) -> UpdateCache? {
        guard let data = FileManager.default.contents(atPath: paths.updateFile) else { return nil }
        return try? decoder().decode(UpdateCache.self, from: data)
    }

    static func store(_ cache: UpdateCache, _ paths: Paths) throws {
        try FileManager.default.createDirectory(atPath: paths.stateDir, withIntermediateDirectories: true)
        try encoder().encode(cache).write(to: URL(fileURLWithPath: paths.updateFile), options: .atomic)
    }

    /// Failures are silent in the app; the first one of a session is logged here.
    static func log(_ message: String, _ paths: Paths) {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: (paths.logFile as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: paths.logFile) { fm.createFile(atPath: paths.logFile, contents: nil) }
        guard let handle = FileHandle(forWritingAtPath: paths.logFile) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(ISO8601DateFormatter().string(from: Date())) update: \(message)\n".utf8))
    }

    private static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}
