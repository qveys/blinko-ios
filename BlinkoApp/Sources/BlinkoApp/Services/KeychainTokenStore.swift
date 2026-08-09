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
        lastReadStatus = status
        KeychainTokenStore.log("read", status: status)
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
        let status = SecItemAdd(attributes as CFDictionary, nil)
        lastAddStatus = status
        KeychainTokenStore.log("add", status: status)
    }

    private func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseDataProtectionKeychain: true,
        ]
        let status = SecItemDelete(query as CFDictionary)
        lastDeleteStatus = status
        KeychainTokenStore.log("delete", status: status)
    }

    /// Records the SecItem OSStatus for each operation. Diagnostic only — the
    /// simulator keychain round-trip is failing with no visible reason, and the
    /// raw status code (errSecMissingEntitlement -34018, errSecParam, etc.)
    /// tells us which. Stripped once green.
    private static func log(_ op: String, status: OSStatus) {
        let message = "KeychainTokenStore \(op) status=\(status)"
        NSLog("%@", message)
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    #if DEBUG
    /// Last OSStatus from SecItemAdd / SecItemCopyMatching / SecItemDelete.
    /// Diagnostic hook so tests can surface the real failure code instead of a
    /// bare `nil != Optional("...")`.
    private(set) var lastAddStatus: OSStatus = 0
    private(set) var lastReadStatus: OSStatus = 0
    private(set) var lastDeleteStatus: OSStatus = 0
    #endif
}
