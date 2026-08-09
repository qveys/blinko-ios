import Foundation

protocol AuthServiceProtocol: Sendable {
    /// Exchanges credentials for an API token and stores it.
    func login(name: String, password: String) async throws -> User
    /// Clears the stored token.
    func logout() async
}

/// Handles sign-in against `/api/v1/user/login`.
///
/// Blinko issues a long-lived API token (also written to `accounts.apiToken`).
/// There is no refresh endpoint — when a call returns `401`, the only recovery
/// is to sign in again. Users can alternatively paste a Personal Access Token
/// from Blinko's settings UI, which goes into the same token store.
final class AuthService: AuthServiceProtocol {
    private let httpClient: any HTTPClient
    private let tokenStore: InMemoryTokenStore

    init(httpClient: any HTTPClient, tokenStore: InMemoryTokenStore) {
        self.httpClient = httpClient
        self.tokenStore = tokenStore
    }

    func login(name: String, password: String) async throws -> User {
        let response: LoginResponse = try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Auth.login,
                method: .post,
                body: LoginRequest(name: name, password: password),
                requiresAuth: false
            )
        )
        await tokenStore.setToken(response.token)
        return response.user
    }

    func logout() async {
        await tokenStore.setToken(nil)
    }
}
