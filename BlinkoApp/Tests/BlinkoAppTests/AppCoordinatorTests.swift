import XCTest
@testable import BlinkoApp

@MainActor
final class AppCoordinatorTests: XCTestCase {
    private let serverURL = URL(string: "https://blinko.example.com")!

    private func makeCoordinator(token: String? = nil) -> AppCoordinator {
        AppCoordinator(tokenStore: InMemoryTokenStore(token: token))
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
        let coordinator = makeCoordinator(token: nil)
        await coordinator.restoreSession()
        XCTAssertFalse(coordinator.isAuthenticated)
    }

    func testRestoreSessionWithTokenButNoServerURL() async {
        let coordinator = makeCoordinator(token: "tok_abc")
        // No UserDefaults entry for serverURLKey → no restoration.
        await coordinator.restoreSession()
        XCTAssertFalse(coordinator.isAuthenticated)
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

    // MARK: - signOut

    func testSignOutClearsAuthentication() async {
        let coordinator = makeCoordinatorWithMockAuth(token: "tok_test")
        await coordinator.signIn(withToken: "tok_test")
        XCTAssertTrue(coordinator.isAuthenticated)

        await coordinator.signOut()
        XCTAssertFalse(coordinator.isAuthenticated)
        XCTAssertNil(coordinator.currentUser)
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
