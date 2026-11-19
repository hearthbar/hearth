import Foundation
import Security

/// Minimal generic-password Keychain wrapper.
enum Keychain {
    private static let service = "com.brianhubbell.Hearth"

    /// Demo and screenshot runs keep secrets in memory so they never touch the real Keychain.
    private static let ephemeral: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["HEARTH_DEMO"] == "1" || env["HEARTH_ONBOARDING"] == "1"
    }()
    nonisolated(unsafe) private static var memory: [String: String] = [:]

    static func get(_ key: String) -> String? {
        if ephemeral { return memory[key] }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for key: String) {
        guard let value else { delete(key); return }
        if ephemeral { memory[key] = value; return }
        let data = Data(value.utf8)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ key: String) {
        if ephemeral { memory[key] = nil; return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: Typed helpers

    static var config: NestConfig? {
        get { get("config").flatMap { try? JSONDecoder().decode(NestConfig.self, from: Data($0.utf8)) } }
        set {
            let json = newValue.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
            set(json, for: "config")
        }
    }

    static var refreshToken: String? {
        get { get("refresh_token") }
        set { set(newValue, for: "refresh_token") }
    }
}
