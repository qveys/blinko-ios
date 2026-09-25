import XCTest
@testable import BlinkoApp

/// Tests for the BLI-33 offline fallback in `HomeViewModel`: stale fallback
/// on retryable failures, cache updates on success, preservation of on-screen
/// content across a failed refresh, and the auth-error exception.
@MainActor
final class HomeViewModelOfflineTests: XCTestCase {
    private static func sampleNote(id: Int, content: String = "note") -> Note {
        Note(id: id, content: content, createdAt: Date(), updatedAt: Date())
    }

    // MARK: - Cold launch, no network

    func testRetryableFailureFallsBackToCachedNotes() async {
        let cached = [Self.sampleNote(id: 1, content: "from cache")]
        let cacheStore = InMemoryNotesCacheStore()
        await cacheStore.save(notes: cached, savedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let viewModel = HomeViewModel(
            noteService: MockNoteService(error: APIError.transport("offline")),
            cacheStore: cacheStore
        )

        await viewModel.loadNotes()

        XCTAssertEqual(viewModel.notes.map(\.content), ["from cache"])
        XCTAssertTrue(viewModel.isShowingStaleData)
        XCTAssertEqual(viewModel.staleDataTimestamp, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertFalse(viewModel.showError, "Cached fallback should banner, not alert")
    }

    func testTimeoutAlsoFallsBackToCache() async {
        let cacheStore = InMemoryNotesCacheStore()
        await cacheStore.save(notes: [Self.sampleNote(id: 1)], savedAt: Date())
        let viewModel = HomeViewModel(
            noteService: MockNoteService(error: APIError.timedOut),
            cacheStore: cacheStore
        )

        await viewModel.loadNotes()

        XCTAssertFalse(viewModel.notes.isEmpty)
        XCTAssertTrue(viewModel.isShowingStaleData)
    }

    func testRetryableFailureWithEmptyCacheStillErrors() async {
        let viewModel = HomeViewModel(
            noteService: MockNoteService(error: APIError.transport("offline")),
            cacheStore: InMemoryNotesCacheStore()
        )

        await viewModel.loadNotes()

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.isShowingStaleData)
    }

    // MARK: - Auth failures must not show cached content

    /// A 401 means this session is over; showing the previous session's notes
    /// would leak content past sign-out. The re-auth flow must win.
    func testUnauthorizedDoesNotFallBackToCache() async {
        let cacheStore = InMemoryNotesCacheStore()
        await cacheStore.save(notes: [Self.sampleNote(id: 1)], savedAt: Date())
        let viewModel = HomeViewModel(
            noteService: MockNoteService(error: APIError.unauthorized(message: nil)),
            cacheStore: cacheStore
        )

        await viewModel.loadNotes()

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertTrue(viewModel.requiresReauthentication)
        XCTAssertFalse(viewModel.isShowingStaleData)
    }

    // MARK: - Successful refresh

    func testSuccessfulLoadSavesToCache() async {
        let cacheStore = InMemoryNotesCacheStore()
        let viewModel = HomeViewModel(
            noteService: MockNoteService(notes: [Self.sampleNote(id: 42)]),
            cacheStore: cacheStore
        )

        await viewModel.loadNotes()

        let payload = await cacheStore.load()
        XCTAssertEqual(payload?.notes.map(\.id), [42])
    }

    func testSuccessfulLoadClearsStaleFlag() async {
        let cacheStore = InMemoryNotesCacheStore()
        await cacheStore.save(notes: [Self.sampleNote(id: 1)], savedAt: Date())
        let failing = HomeViewModel(
            noteService: MockNoteService(error: APIError.transport("offline")),
            cacheStore: cacheStore
        )
        await failing.loadNotes()
        XCTAssertTrue(failing.isShowingStaleData)

        // Same cache, now a reachable server: the flag must clear.
        let recovered = HomeViewModel(
            noteService: MockNoteService(notes: [Self.sampleNote(id: 2)]),
            cacheStore: cacheStore
        )
        await recovered.loadNotes()

        XCTAssertFalse(recovered.isShowingStaleData)
        XCTAssertNil(recovered.staleDataTimestamp)
    }

    /// Server-side deletions reconcile through wholesale replacement: after a
    /// successful refresh the cache holds exactly the fresh payload.
    func testSuccessfulRefreshReconcilesDeletionsInCache() async {
        let cacheStore = InMemoryNotesCacheStore()
        await cacheStore.save(
            notes: [Self.sampleNote(id: 1), Self.sampleNote(id: 2)],
            savedAt: Date()
        )
        // Note 2 no longer exists on the server.
        let viewModel = HomeViewModel(
            noteService: MockNoteService(notes: [Self.sampleNote(id: 1)]),
            cacheStore: cacheStore
        )

        await viewModel.loadNotes()

        let payload = await cacheStore.load()
        XCTAssertEqual(payload?.notes.map(\.id), [1])
    }

    // MARK: - Failed pull-to-refresh preserves screen content

    func testFailedRefreshKeepsExistingNotesOnScreen() async {
        let cacheStore = InMemoryNotesCacheStore()
        let viewModel = HomeViewModel(
            noteService: FlakyNoteService(
                first: .success([Self.sampleNote(id: 1, content: "loaded")]),
                then: .failure(APIError.transport("offline"))
            ),
            cacheStore: cacheStore
        )
        await viewModel.loadNotes()
        XCTAssertEqual(viewModel.notes.count, 1)

        await viewModel.loadNotes() // pull-to-refresh, now offline

        XCTAssertEqual(
            viewModel.notes.map(\.content), ["loaded"],
            "Retryable refresh failure must not blank the list"
        )
        XCTAssertTrue(viewModel.isShowingStaleData)
        XCTAssertFalse(viewModel.showError)
    }

    // MARK: - Paging while stale

    func testCannotLoadMoreWhileShowingStaleData() async {
        let cacheStore = InMemoryNotesCacheStore()
        // A full page would normally mean hasMore = true.
        let fullPage = (1...SyncMetadata.defaultPageSize).map { Self.sampleNote(id: $0) }
        await cacheStore.save(notes: fullPage, savedAt: Date())
        let viewModel = HomeViewModel(
            noteService: MockNoteService(error: APIError.transport("offline")),
            cacheStore: cacheStore
        )

        await viewModel.loadNotes()

        XCTAssertTrue(viewModel.isShowingStaleData)
        XCTAssertFalse(viewModel.canLoadMore, "The cache only holds page 1; paging needs the server")
    }
}

/// Succeeds on the first `fetchNotes` and returns `then` afterwards — the
/// smallest seam that exercises "refresh fails after a good launch load".
private actor FlakyNoteService: NoteServiceProtocol {
    private let first: Result<[Note], APIError>
    private let then: Result<[Note], APIError>
    private var callCount = 0

    init(first: Result<[Note], APIError>, then: Result<[Note], APIError>) {
        self.first = first
        self.then = then
    }

    func fetchNotes(_ request: NoteListRequest) async throws -> [Note] {
        callCount += 1
        return try (callCount == 1 ? first : then).get()
    }

    func fetchNote(id: Int) async throws -> Note { throw APIError.notFound(message: nil) }
    func createNote(content: String, type: NoteType) async throws -> Note {
        throw APIError.notConfigured
    }
    func updateContent(id: Int, content: String) async throws -> Note {
        throw APIError.notConfigured
    }
    func upsert(_ request: NoteUpsertRequest) async throws -> Note {
        throw APIError.notConfigured
    }
    func setTop(id: Int, isTop: Bool) async throws -> Note { throw APIError.notConfigured }
    func setArchived(id: Int, isArchived: Bool) async throws -> Note {
        throw APIError.notConfigured
    }
    func trash(ids: [Int]) async throws { throw APIError.notConfigured }
    func restore(ids: [Int]) async throws { throw APIError.notConfigured }
    func delete(ids: [Int]) async throws { throw APIError.notConfigured }
}
