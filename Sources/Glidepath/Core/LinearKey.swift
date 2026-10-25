import Foundation
import Security

/// The Linear API key, in the login Keychain. The key never goes on a command line.
enum LinearKey {
    static let service = "dev.glidepath.linear"
    static let account = "linear"

    private static func query() -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func read() -> String? {
        var q = query()
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) throws {
        let update = [kSecValueData as String: Data(key.utf8)] as CFDictionary
        var status = SecItemUpdate(query() as CFDictionary, update)
        if status == errSecItemNotFound {
            var add = query()
            add[kSecValueData as String] = Data(key.utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw LinearKeyError(status: status) }
    }

    static func remove() {
        _ = SecItemDelete(query() as CFDictionary)
    }
}

struct LinearKeyError: Error, CustomStringConvertible {
    let status: OSStatus
    var description: String { "Keychain error \(status)" }
}
