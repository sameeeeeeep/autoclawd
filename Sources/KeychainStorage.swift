import Foundation
import Security

// MARK: - AppSettingsStorage
//
// Priority order for sensitive values (API keys):
//   1. Environment variable  — zero friction, works in shell + launchd
//   2. Keychain              — encrypted at rest, macOS native
//   3. Legacy .settings file — one-time migration only
//
// Set env vars in ~/.zshenv or via launchctl:
//   GROQ_API_KEY=sk-...
//   ANTHROPIC_API_KEY=sk-ant-...
//
// Environment-variable names are derived from the account key automatically:
//   "groq_api_key_storage"     → GROQ_API_KEY
//   "anthropic_api_key_storage" → ANTHROPIC_API_KEY
// You can also set the exact uppercased key as the env var.

enum AppSettingsStorage {
    private static let service = Bundle.main.bundleIdentifier ?? "com.autoclawd.app"

    // MARK: - Known env var mappings

    private static let envVarMap: [String: String] = [
        "groq_api_key_storage":      "GROQ_API_KEY",
        "anthropic_api_key_storage": "ANTHROPIC_API_KEY",
    ]

    // MARK: - Public API

    static func load(account: String) -> String? {
        // 1. Environment variable (highest priority — no keychain prompt)
        let envKey = envVarMap[account] ?? account.uppercased().replacingOccurrences(of: "_STORAGE", with: "")
        if let envVal = ProcessInfo.processInfo.environment[envKey], !envVal.isEmpty {
            return envVal
        }

        // 2. Try Keychain
        if let val = keychainLoad(account: account) { return val }

        // 3. One-time migration from legacy .settings JSON file
        if let val = legacyLoad(account: account) {
            keychainSave(val, account: account)
            legacyDelete(account: account)
            Log.info(.system, "Keychain: migrated '\(account)' from legacy file")
            return val
        }
        return nil
    }

    static func save(_ value: String, account: String) {
        // When a value is saved explicitly (via UI), store it in Keychain.
        // Env-var values are never written back to Keychain — they're read-only.
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
