import Foundation

/// Persists the Blinko server URL in UserDefaults.
///
/// The server URL is not a secret — it is user-supplied and visible in the UI
/// — so it lives in UserDefaults rather than the Keychain. The auth token is
/// handled separately by ``KeychainTokenStore``.
///
/// Using a protocol lets tests inject an in-memory stub without touching
/// `UserDefaults.standard`, which would pollute the test host.
protocol ServerConfigStore: Sendable {
    var serverURL: URL? { get }
    func save(serverURL: URL)
    func clear()
}

/// UserDefaults-backed implementation used in production.
struct UserDefaultsServerConfigStore: ServerConfigStore {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "blinko.serverURL") {
        self.defaults = defaults
        self.key = key
    }

    var serverURL: URL? {
        defaults.string(forKey: key).flatMap { URL(string: $0) }
    }

    func save(serverURL: URL) {
        defaults.set(serverURL.absoluteString, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

/// In-memory stub for tests and previews.
final class InMemoryServerConfigStore: ServerConfigStore, @unchecked Sendable {
    private(set) var serverURL: URL?

    init(serverURL: URL? = nil) {
        self.serverURL = serverURL
    }

    func save(serverURL: URL) {
        self.serverURL = serverURL
    }

    func clear() {
        serverURL = nil
    }
}
