import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var serverURL: URL?
    /// Built once a server is configured; `nil` until then.
    @Published private(set) var services: ServiceContainer?
    @Published private(set) var currentUser: User?

    private let tokenStore: any TokenStore
    private let serverConfigStore: any ServerConfigStore

    init(
        tokenStore: any TokenStore = KeychainTokenStore(),
        serverConfigStore: any ServerConfigStore = UserDefaultsServerConfigStore()
    ) {
        self.tokenStore = tokenStore
        self.serverConfigStore = serverConfigStore
    }

    /// Testing entry point: pre-wires a `ServiceContainer` without network setup.
    init(tokenStore: any TokenStore = InMemoryTokenStore(), services: ServiceContainer) {
        self.tokenStore = tokenStore
        self.serverConfigStore = InMemoryServerConfigStore(serverURL: services.serverURL)
        self.services = services
        self.serverURL = services.serverURL
    }

    /// Testing entry point: injects both stores without network setup.
    init(
        tokenStore: any TokenStore,
        serverConfigStore: any ServerConfigStore
    ) {
        self.tokenStore = tokenStore
        self.serverConfigStore = serverConfigStore
    }

    /// Restores a previous session from Keychain + persistent config.
    ///
    /// Call once from `BlinkoApp.init` or `.task` on the root scene.
    func restoreSession() async {
        guard
            let url = serverConfigStore.serverURL,
            let token = await tokenStore.token, !token.isEmpty
        else { return }
        serverURL = url
        services = ServiceContainer(serverURL: url, tokenStore: tokenStore)
        isAuthenticated = true
    }

    /// Points the app at a Blinko instance, preserving any stored token.
    func configure(serverURL: URL) {
        self.serverURL = serverURL
        serverConfigStore.save(serverURL: serverURL)
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
        serverConfigStore.clear()
        isAuthenticated = false
        currentUser = nil
        serverURL = nil
        services = nil
    }

    /// Call when any API call returns `.unauthorized`. Routes the user back to sign-in.
    func handleUnauthorized() async {
        await signOut()
    }
}
