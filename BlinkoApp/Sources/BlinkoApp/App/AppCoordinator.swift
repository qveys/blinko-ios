import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var serverURL: URL?
    /// Built once a server is configured; `nil` until then.
    @Published private(set) var services: ServiceContainer?
    @Published private(set) var currentUser: User?

    private let tokenStore: any TokenStore
    private let serverURLKey = "blinko.serverURL"

    init(tokenStore: any TokenStore = KeychainTokenStore()) {
        self.tokenStore = tokenStore
    }

    /// Testing entry point: pre-wires a `ServiceContainer` without network setup.
    init(tokenStore: any TokenStore = InMemoryTokenStore(), services: ServiceContainer) {
        self.tokenStore = tokenStore
        self.services = services
        self.serverURL = services.serverURL
    }

    /// Restores a previous session from Keychain + UserDefaults.
    /// Call once from `BlinkoApp.init` or `.task` on the root scene.
    func restoreSession() async {
        guard
            let raw = UserDefaults.standard.string(forKey: serverURLKey),
            let url = URL(string: raw),
            let token = await tokenStore.token, !token.isEmpty
        else { return }
        serverURL = url
        services = ServiceContainer(serverURL: url, tokenStore: tokenStore)
        isAuthenticated = true
    }

    /// Points the app at a Blinko instance, preserving any stored token.
    func configure(serverURL: URL) {
        self.serverURL = serverURL
        UserDefaults.standard.set(serverURL.absoluteString, forKey: serverURLKey)
        self.services = ServiceContainer(serverURL: serverURL, tokenStore: tokenStore)
        self.isAuthenticated = false
        self.currentUser = nil
    }

    /// Signs in with username + password credentials against the configured server.
    func signIn(name: String, password: String) async throws {
        guard let services else { throw APIError.notConfigured }
        currentUser = try await services.authService.login(name: name, password: password)
        isAuthenticated = true
    }

    /// Signs in with a Personal Access Token pasted from Blinko's settings UI.
    func signIn(withToken token: String) async {
        guard services != nil else { return }
        await tokenStore.setToken(token)
        isAuthenticated = true
    }

    func signOut() async {
        await services?.authService.logout()
        // Drop the tags cache with the session: the next sign-in on this
        // device may be a different account, which must not see these tags.
        await services?.tagsCacheStore.clear()
        UserDefaults.standard.removeObject(forKey: serverURLKey)
        isAuthenticated = false
        currentUser = nil
    }

    /// Call when any API call returns `.unauthorized`. Routes the user back to sign-in.
    func handleUnauthorized() async {
        await signOut()
    }
}
