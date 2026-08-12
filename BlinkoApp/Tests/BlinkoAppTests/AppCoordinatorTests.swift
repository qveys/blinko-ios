import XCTest
@testable import BlinkoApp

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private let serverURL = URL(string: "https://blinko.example.com")!

    private func makeCoordinator(
        token: String? = nil,
        configuredServerURL: URL? = nil
    ) -> AppCoordinator {
        AppCoordinator(
            tokenStore: InMemoryTokenStore(token: token),
            serverConfigStore: InMemoryServerConfigStore(serverURL: configuredServerURL)
        )
    }

    private func makeCoordinatorWithMockAuth(token: String? = nil) -> AppCoordinator {
        let store = InMemoryTokenStore(token: token)
        let container = ServiceContainer(
            serverURL: serverURL,
            tokenStore: store,
            noteService: MockNoteService(),
            tagService: MockTagService(),
            authService: MockAuthService()
        )
        return AppCoordinator(tokenStore: store, services: container)
    }

    // MARK: - restoreSession

    func testRestoreSessionWithNoToken() async {
        let coordinator = makeCoordinator(token: nil, configuredServerURL: serverURL)
        await coordinator.restoreSession()
        XCTAssertFalse(coordinator.isAuthenticated)
    }

    func testRestoreSessionWithTokenButNoServerURL() async {
        let coordinator = makeCoordinator(token: "tok_abc", configuredServerURL: nil)
        await coordinator.restoreSession()
        XCTAssertFalse(coordinator.isAuthenticated)
    }

    /// An empty-string token is treated as absent — it would produce an
    /// `Authorization: Bearer ` header the server rejects.
    func testRestoreSessionWithEmptyTokenDoesNotAuthenticate() async {
        let coordinator = makeCoordinator(token: "", configuredServerURL: serverURL)
        await coordinator.restoreSession()
        XCTAssertFalse(coordinator.isAuthenticated)
    }

    /// The relaunch path: token in the Keychain and URL in config together
    /// restore an authenticated session with no re-login.
    func testRestoreSessionWithTokenAndServerURL() async {
        let coordinator = makeCoordinator(token: "tok_abc", configuredServerURL: serverURL)
        await coordinator.restoreSession()
        XCTAssertTrue(coordinator.isAuthenticated)
        XCTAssertEqual(coordinator.serverURL, serverURL)
        XCTAssertNotNil(coordinator.services)
    }

    // MARK: - configure

    func testConfigurePersistsServerURL() async {
        let configStore = InMemoryServerConfigStore()
        let coordinator = AppCoordinator(
            tokenStore: InMemoryTokenStore(),
            serverConfigStore: configStore
        )
        coordinator.configure(serverURL: serverURL)
        XCTAssertEqual(configStore.serverURL, serverURL)
        XCTAssertEqual(coordinator.serverURL, serverURL)
    }

    // MARK: - signIn (credentials)

    func testSignInWithCredentials() async throws {
        let coordinator = makeCoordinatorWithMockAuth()
        try await coordinator.signIn(name: "alice", password: "secret")
        XCTAssertTrue(coordinator.isAuthenticated)
        XCTAssertNotNil(coordinator.currentUser)
    }

    func testSignInWithoutConfigurationThrows() async {
        let coordinator = makeCoordinator()
        do {
            try await coordinator.signIn(name: "alice", password: "secret")
            XCTFail("Expected .notConfigured")
        } catch APIError.notConfigured {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - signIn (PAT)

    func testSignInWithToken() async {
        let coordinator = makeCoordinator()
        coordinator.configure(serverURL: serverURL)
        await coordinator.signIn(withToken: "pat_xyz")
        XCTAssertTrue(coordinator.isAuthenticated)
    }

    /// A PAT is written to the token store so it survives relaunch, exactly
    /// like a password login.
    func testSignInWithTokenPersistsToTokenStore() async {
        let tokenStore = InMemoryTokenStore()
        let coordinator = AppCoordinator(
            tokenStore: tokenStore,
            serverConfigStore: InMemoryServerConfigStore()
        )
        coordinator.configure(serverURL: serverURL)
        await coordinator.signIn(withToken: "pat_xyz")
        let stored = await tokenStore.token
        XCTAssertEqual(stored, "pat_xyz")
    }

    // MARK: - signOut

    func testSignOutClearsAuthentication() async {
        let coordinator = makeCoordinatorWithMockAuth(token: "tok_test")
        await coordinator.signIn(withToken: "tok_test")
        XCTAssertTrue(coordinator.isAuthenticated)

        await coordinator.signOut()
        XCTAssertFalse(coordinator.isAuthenticated)
        XCTAssertNil(coordinator.currentUser)
    }

    /// Sign-out must clear the persisted server URL, otherwise the next launch
    /// restores a half-configured session.
    func testSignOutClearsPersistedServerURL() async {
        let configStore = InMemoryServerConfigStore()
        let coordinator = AppCoordinator(
            tokenStore: InMemoryTokenStore(),
            serverConfigStore: configStore
        )
        coordinator.configure(serverURL: serverURL)
        await coordinator.signIn(withToken: "tok_test")

        await coordinator.signOut()
        XCTAssertNil(configStore.serverURL)
        XCTAssertNil(coordinator.serverURL)
        XCTAssertNil(coordinator.services)
    }

    /// After sign-out, a fresh restore attempt must not resurrect the session.
    func testRestoreAfterSignOutDoesNotAuthenticate() async {
        let tokenStore = InMemoryTokenStore()
        let configStore = InMemoryServerConfigStore()
        let coordinator = AppCoordinator(
            tokenStore: tokenStore,
            serverConfigStore: configStore
        )
        coordinator.configure(serverURL: serverURL)
        await coordinator.signIn(withToken: "tok_test")
        await coordinator.signOut()

        await coordinator.restoreSession()
        XCTAssertFalse(coordinator.isAuthenticated)
    }

    // MARK: - handleUnauthorized

    func testHandleUnauthorizedSignsOut() async {
        let coordinator = makeCoordinatorWithMockAuth(token: "tok_stale")
        await coordinator.signIn(withToken: "tok_stale")
        XCTAssertTrue(coordinator.isAuthenticated)

        await coordinator.handleUnauthorized()
        XCTAssertFalse(coordinator.isAuthenticated)
    }
}

// MARK: - Test double

private actor MockAuthService: AuthServiceProtocol {
    func login(name: String, password: String) async throws -> User {
        User(id: 1, name: name, nickname: name, image: "", role: "user", loginType: "password")
    }
    func logout() async {}
}
