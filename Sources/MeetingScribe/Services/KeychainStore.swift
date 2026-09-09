import Foundation
import Security

enum KeychainStore {
    private static let service = "com.junowozlabs.MeetingScribe"
    private static let migrationKey = "legacy-keychain-migration-complete"
    private static let account = "assemblyai-api-key"

    static func saveAPIKey(_ value: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        guard !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    static func loadAPIKey() -> String {
        let current = load(service: service)
        guard current.isEmpty, !UserDefaults.standard.bool(forKey: migrationKey) else { return current }
        let legacy = load(service: LegacyMigration.legacyBundleIdentifier)
        guard !legacy.isEmpty else { return "" }
        do { try saveAPIKey(legacy); return legacy }
        catch { return "" }
    }

    private static func load(service: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    enum KeychainError: LocalizedError {
        case status(OSStatus)
        var errorDescription: String? {
            switch self { case .status(let value): "Não foi possível salvar a chave no Keychain (\(value))." }
        }
    }
}
