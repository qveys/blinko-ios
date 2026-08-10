import Combine
import Foundation

/// Wires the networking stack to the services that use it.
///
/// A Blinko instance is self-hosted, so there is no default server — the
/// container is built once the user supplies a URL during onboarding, and
/// rebuilt if they point the app at a different server.
@MainActor
final class ServiceContainer: ObservableObject {
    /// Origin of the Blinko instance, e.g. `https://blinko.example.com`.
    let serverURL: URL

    let tokenStore: any TokenStore
    let noteService: any NoteServiceProtocol
    let tagService: any TagServiceProtocol
    let authService: any AuthServiceProtocol
    /// Offline read cache for the tag filter sheet, keyed to this
    /// container's server. Cleared on sign-out by the coordinator.
    let tagsCacheStore: any TagsCacheStore

    init(serverURL: URL, session: URLSession = .shared, tokenStore: any TokenStore = KeychainTokenStore()) {
        self.serverURL = serverURL
        self.tokenStore = tokenStore

        let httpClient = URLSessionHTTPClient(
            baseURL: BlinkoAPI.baseURL(forServer: serverURL),
            session: session,
            tokenProvider: tokenStore
        )
        self.noteService = NoteService(httpClient: httpClient)
        self.tagService = TagService(httpClient: httpClient)
        self.authService = AuthService(httpClient: httpClient, tokenStore: tokenStore)
        self.tagsCacheStore = FileTagsCacheStore(serverURL: serverURL)
    }

    /// Container built from explicit services, for previews and tests.
    init(
        serverURL: URL,
        tokenStore: any TokenStore,
        noteService: any NoteServiceProtocol,
        tagService: any TagServiceProtocol,
        authService: any AuthServiceProtocol,
        tagsCacheStore: (any TagsCacheStore)? = nil
    ) {
        self.serverURL = serverURL
        self.tokenStore = tokenStore
        self.noteService = noteService
        self.tagService = tagService
        self.authService = authService
        self.tagsCacheStore = tagsCacheStore ?? InMemoryTagsCacheStore(serverURL: serverURL)
    }
}
