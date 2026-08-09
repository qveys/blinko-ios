import Foundation
import Security

/// Persists the Blinko API token in the iOS Keychain so it survives app restarts.
///
/// Uses a `kSecClassGenericPassword` item keyed by `service` + `account`, with no
/// access group. That keeps the item in the per-app file-based keychain partition
/// and avoids any keychain-access-groups entitlement — the single-app token needs
/// neither sharing nor the data-protection keychain, which would require signing
/// with an entitlement the app does not carry.
///
/// All Keychain calls are synchronous and run on the actor's executor, so the
/// actor wrapper satisfies `Sendable` without additional locking.
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
        ]
        SecItemDelete(query as CFDictionary)
    }
}
