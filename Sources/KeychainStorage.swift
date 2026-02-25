import Foundation
import Security

// MARK: - AppSettingsStorage
//
// Stores sensitive values (API keys) in the macOS Keychain using SecItem APIs.
// Values are encrypted at rest and only accessible when the device is unlocked.
//
// Interface is intentionally identical to the old file-backed version so all
// call sites in SettingsManager.swift require zero changes.
//
// One-time migration: on first load(), if the Keychain has no entry, checks the
// legacy .settings JSON file, migrates to Keychain, and removes from the file.

enum AppSettingsStorage {
    private static let service = Bundle.main.bundleIdentifier ?? "com.autoclawd.app"

    // MARK: - Public API

    static func load(account: String) -> String? {
        // 1. Try Keychain first
        if let val = keychainLoad(account: account) { return val }
        // 2. One-time migration from legacy .settings JSON file
        if let val = legacyLoad(account: account) {
            keychainSave(val, account: account)
            legacyDelete(account: account)
            Log.info(.system, "Keychain: migrated '\(account)' from legacy file")
            return val
        }
        return nil
    }

    static func save(_ value: String, account: String) {
        keychainSave(value, account: account)
    }

    static func delete(account: String) {
        keychainDelete(account: account)
    }

    // MARK: - Keychain (SecItem)

    private static func keychainLoad(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    service,
            kSecAttrAccount:    account,
            kSecReturnData:     true,
            kSecMatchLimit:     kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else { return nil }
        return str
    }

    private static func keychainSave(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        keychainDelete(account: account) // delete-then-add is the safe update pattern
        let item: [CFString: Any] = [
            kSecClass:          kSecClassGenericPassword,
            kSecAttrService:    service,
            kSecAttrAccount:    account,
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
        ]
        let status = SecItemAdd(item as CFDictionary, nil)
        if status != errSecSuccess {
            Log.error(.system, "Keychain: SecItemAdd failed for '\(account)' — OSStatus \(status)")
        }
    }

    private static func keychainDelete(account: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Legacy Migration (one-time read from old .settings JSON file)

    private static var legacyFileURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "AutoClawd"
        return appSupport
            .appendingPathComponent(appName, isDirectory: true)
            .appendingPathComponent(".settings")
    }

    private static func legacyLoad(account: String) -> String? {
        guard let data = try? Data(contentsOf: legacyFileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        return dict[account]
    }

    private static func legacyDelete(account: String) {
        guard let data = try? Data(contentsOf: legacyFileURL),
              var dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return }
        dict.removeValue(forKey: account)
        if let updated = try? JSONEncoder().encode(dict) {
            try? updated.write(to: legacyFileURL, options: .atomic)
        }
    }
}
