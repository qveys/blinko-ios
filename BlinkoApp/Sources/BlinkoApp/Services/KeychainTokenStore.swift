import Foundation
import Security

/// Persists the Blinko API token in the iOS Keychain so it survives app restarts.
///
/// Uses a `kSecClassGenericPassword` item keyed by `service` + `account`.
/// All Keychain calls are synchronous and run on the actor's executor, so the
/// actor wrapper satisfies `Sendable` without additional locking.
///
/// `kSecUseDataProtectionKeychain` is set on every call so the item lives in
/// the data-protection keychain rather than the file-based one. On the
/// simulator the file-based keychain silently partitions items by access group
/// (defaulting to an empty group when none is set), which makes writes appear
/// to succeed while reads return nothing — the data-protection keychain has a
/// single shared partition and round-trips reliably in tests.
actor KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    init(service: String = "com.blinko.ios", account: String = "api-token") {
        self.service = service
        self.account = account
    }

    var token: String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8)
        else { return nil }
        return string
    }

    func setToken(_ token: String?) {
        if let token {
            save(token)
        } else {
            delete()
        }
    }

    private func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        delete()
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    private func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
