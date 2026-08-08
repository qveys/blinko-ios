import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published private(set) var isAuthenticated = false
    @Published private(set) var serverURL: URL?
    /// Built once a server is configured; `nil` until then.
    @Published private(set) var services: ServiceContainer?
    @Published private(set) var currentUser: User?

    /// Points the app at a Blinko instance, discarding any previous session.
    func configure(serverURL: URL) {
        self.serverURL = serverURL
        self.services = ServiceContainer(serverURL: serverURL)
        self.isAuthenticated = false
        self.currentUser = nil
    }

    /// Signs in against the configured server.
    func signIn(name: String, password: String) async throws {
        guard let services else { throw APIError.notConfigured }
        currentUser = try await services.authService.login(name: name, password: password)
        isAuthenticated = true
    }

    /// Signs in with a Personal Access Token pasted from Blinko's settings UI.
    func signIn(withToken token: String) async {
        guard let services else { return }
        await services.tokenStore.setToken(token)
        isAuthenticated = true
    }

    func signOut() async {
        await services?.authService.logout()
        isAuthenticated = false
        currentUser = nil
    }
}
