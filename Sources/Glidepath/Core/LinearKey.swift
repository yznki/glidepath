import Foundation

/// The Linear API key, in the login Keychain as a generic password. It is written and read through `/usr/bin/security`,
/// so that tool is on the item's access list and the launchd job reads it without a prompt. The key never goes on a
/// command line: `save` sends it to `security -i` on stdin.
enum LinearKey {
    static let service = "dev.glidepath.linear"
    static let account = "linear"
    static let security = "/usr/bin/security"

    /// The stored key, trimmed. Nil when there is none or `security` cannot read it.
    static func read() -> String? {
        let r = Shell.run(security, ["find-generic-password", "-s", service, "-a", account, "-w"])
        guard r.ok else { return nil }
        let key = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// A key Linear issues: 8 to 200 letters, digits, `-` or `_`. Anything else never reaches the Keychain.
    static func valid(_ key: String) -> Bool {
        key.range(of: "^[A-Za-z0-9_-]{8,200}$", options: .regularExpression) != nil
    }

    static func save(_ key: String) throws {
        guard valid(key) else {
            throw LinearKeyError(message: "A Linear key is 8 to 200 letters, digits, - or _.")
        }
        let command = "add-generic-password -U -s \(service) -a \(account) -w \"\(key)\"\n"
        let r = Shell.run(security, ["-i"], input: command)
        guard r.ok else {
            throw LinearKeyError(message: "Keychain refused the key: \(r.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }

    static func remove() {
        _ = Shell.run(security, ["delete-generic-password", "-s", service, "-a", account])
    }
}

struct LinearKeyError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}
