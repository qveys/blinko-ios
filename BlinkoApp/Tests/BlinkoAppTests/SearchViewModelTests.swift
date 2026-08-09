import XCTest
@testable import BlinkoApp

@MainActor
final class SearchViewModelTests: XCTestCase {

    /// A debounce far longer than any test run means the `didSet` timer never
    /// fires on its own — each test drives requests explicitly through
    /// `submitSearch()` (which cancels the timer), so exactly one request per
    /// submit reaches the service. Debounce coalescing gets its own test with
    /// a short interval.
    private func makeViewModel(
        service: any NoteServiceProtocol,
        debounce: Duration = .seconds(60)
    ) -> SearchViewModel {
        SearchViewModel(noteService: service, debounceInterval: debounce)
    }

    // MARK: - Searching

    func testSubmitSearchPopulatesMatchingResults() async {
        let notes = [
            Self.note(id: 1, content: "Swift concurrency deep dive"),
            Self.note(id: 2, content: "Grocery list"),
            Self.note(id: 3, content: "swift ui layout notes"),
        ]
        let viewModel = makeViewModel(service: MockNoteService(notes: notes))

        viewModel.query = "swift"
        await viewModel.submitSearch()

        XCTAssertEqual(Set(viewModel.results.map(\.id)), [1, 3])
        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertFalse(viewModel.isSearching)
        XCTAssertFalse(viewModel.showError)
    }

    func testSearchSendsTrimmedQueryToService() async {
        let service = RecordingNoteService()
        let viewModel = makeViewModel(service: service)

        viewModel.query = "  swift  "
        await viewModel.submitSearch()

        let requests = await service.requests
        XCTAssertEqual(requests.map(\.searchText), ["swift"])
    }

    func testNoResultsStateAfterSearchCompletes() async {
        let viewModel = makeViewModel(service: MockNoteService(notes: [
            Self.note(id: 1, content: "Nothing relevant"),
        ]))

        viewModel.query = "zzz-no-match"
        await viewModel.submitSearch()

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertTrue(viewModel.hasSearched)
        XCTAssertFalse(viewModel.showError)
    }

    func testEmptyQuerySubmitResetsWithoutCallingService() async {
        let service = RecordingNoteService()
        let viewModel = makeViewModel(service: service)

        viewModel.query = "   "
        await viewModel.submitSearch()

        let requests = await service.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
    }

    func testClearingQueryResetsResults() async {
        let viewModel = makeViewModel(service: MockNoteService(notes: [
            Self.note(id: 1, content: "swift"),
        ]))
        viewModel.query = "swift"
        await viewModel.submitSearch()
        XCTAssertFalse(viewModel.results.isEmpty)

        viewModel.query = ""
        // The reset is synchronous in the property observer.
        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
        XCTAssertFalse(viewModel.isSearching)
    }

    // MARK: - Errors

    func testSearchFailureShowsError() async {
        let viewModel = makeViewModel(
            service: MockNoteService.failing(APIError.transport("offline"))
        )

        viewModel.query = "swift"
        await viewModel.submitSearch()

        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
        XCTAssertFalse(viewModel.requiresReauthentication)
        XCTAssertFalse(viewModel.isSearching)
    }

    func testUnauthorizedRequestsReauthenticationInsteadOfGenericError() async {
        let viewModel = makeViewModel(
            service: MockNoteService.failing(APIError.unauthorized(message: nil))
        )

        viewModel.query = "swift"
        await viewModel.submitSearch()

        XCTAssertTrue(viewModel.requiresReauthentication)
        XCTAssertFalse(viewModel.showError)
    }

    func testRetryAfterFailureClearsError() async {
        let flaky = FlakyNoteService(
            error: APIError.transport("offline"),
            thenNotes: [Self.note(id: 1, content: "swift")]
        )
        let viewModel = makeViewModel(service: flaky)

        viewModel.query = "swift"
        await viewModel.submitSearch()
        XCTAssertTrue(viewModel.showError)

        await viewModel.submitSearch()
        XCTAssertFalse(viewModel.showError)
        XCTAssertTrue(viewModel.errorMessage.isEmpty)
        XCTAssertEqual(viewModel.results.map(\.id), [1])
    }

    // MARK: - Debounce

    func testTypingBurstCoalescesIntoOneRequest() async throws {
        let service = RecordingNoteService()
        let viewModel = makeViewModel(service: service, debounce: .milliseconds(50))

        viewModel.query = "s"
        viewModel.query = "sw"
        viewModel.query = "swi"
        viewModel.query = "swift"

        // Wait past the debounce for the single trailing request to land.
        try await Task.sleep(for: .milliseconds(400))

        let requests = await service.requests
        XCTAssertEqual(requests.map(\.searchText), ["swift"])
    }

    // MARK: - Stale response ordering

    /// The core race: a response for an older query lands *after* the newer
    /// query's response. The stale payload must be dropped, not applied.
    func testStaleResponseArrivingLateIsDiscarded() async throws {
        let gate = GatedNoteService()
        let viewModel = makeViewModel(service: gate)

        // Start search #1 and let its request depart, but hold its response.
        viewModel.query = "first"
        let first = Task { await viewModel.submitSearch() }
        try await gate.waitForPendingRequests(count: 1)

        // Start search #2 while #1 is still in flight, and hold it too.
        viewModel.query = "second"
        let second = Task { await viewModel.submitSearch() }
        try await gate.waitForPendingRequests(count: 2)

        // Release out of order: newest first, stale one afterwards.
        await gate.release(query: "second", with: [Self.note(id: 2, content: "second result")])
        _ = await second.value
        await gate.release(query: "first", with: [Self.note(id: 1, content: "first result")])
        _ = await first.value

        XCTAssertEqual(viewModel.results.map(\.id), [2], "stale response must not overwrite newer results")
        XCTAssertFalse(viewModel.isSearching)
    }

    /// A stale *failure* must not surface an error over newer results either.
    func testStaleFailureIsDiscarded() async throws {
        let gate = GatedNoteService()
        let viewModel = makeViewModel(service: gate)

        viewModel.query = "first"
        let first = Task { await viewModel.submitSearch() }
        try await gate.waitForPendingRequests(count: 1)

        viewModel.query = "second"
        let second = Task { await viewModel.submitSearch() }
        try await gate.waitForPendingRequests(count: 2)

        await gate.release(query: "second", with: [Self.note(id: 2, content: "second result")])
        _ = await second.value
        await gate.fail(query: "first", with: APIError.transport("offline"))
        _ = await first.value

        XCTAssertEqual(viewModel.results.map(\.id), [2])
        XCTAssertFalse(viewModel.showError, "a stale failure must not raise the error alert")
    }

    /// Clearing the field while a search is in flight: the late response must
    /// not repopulate the emptied list.
    func testResponseArrivingAfterClearIsDiscarded() async throws {
        let gate = GatedNoteService()
        let viewModel = makeViewModel(service: gate)

        viewModel.query = "swift"
        let search = Task { await viewModel.submitSearch() }
        try await gate.waitForPendingRequests(count: 1)

        viewModel.query = ""
        await gate.release(query: "swift", with: [Self.note(id: 1, content: "swift")])
        _ = await search.value

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertFalse(viewModel.hasSearched)
    }

    // MARK: - Pagination

    func testLoadMoreAppendsNextPage() async {
        // 35 matching notes with a page size of 30 → second page has 5.
        let notes = (1...35).map { Self.note(id: $0, content: "swift note \($0)") }
        let viewModel = makeViewModel(service: MockNoteService(notes: notes))

        viewModel.query = "swift"
        await viewModel.submitSearch()
        XCTAssertEqual(viewModel.results.count, 30)
        XCTAssertTrue(viewModel.canLoadMore)

        await viewModel.loadMoreResults()
        XCTAssertEqual(viewModel.results.count, 35)
        XCTAssertFalse(viewModel.canLoadMore, "a short page means no more results")
    }

    func testLoadMoreWithoutSearchIsANoOp() async {
        let service = RecordingNoteService()
        let viewModel = makeViewModel(service: service)

        await viewModel.loadMoreResults()

        let requests = await service.requests
        XCTAssertTrue(requests.isEmpty)
    }

    // MARK: - Detail hosting

    func testOpenAndDismissDetail() {
        let note = Self.note(id: 1, content: "swift")
        let viewModel = makeViewModel(service: MockNoteService(notes: [note]))

        viewModel.open(note)
        XCTAssertEqual(viewModel.selectedNote, note)

        viewModel.dismissDetail()
        XCTAssertNil(viewModel.selectedNote)
    }

    func testNoteSavedUpdatesMatchingResultInPlace() async {
        let notes = [Self.note(id: 1, content: "swift one"), Self.note(id: 2, content: "swift two")]
        let viewModel = makeViewModel(service: MockNoteService(notes: notes))
        viewModel.query = "swift"
        await viewModel.submitSearch()

        var edited = notes[0]
        edited.content = "swift one, edited"
        viewModel.noteSaved(edited)

        XCTAssertEqual(viewModel.results.first?.content, "swift one, edited")
        XCTAssertEqual(viewModel.results.count, 2)
    }

    func testNoteSavedIgnoresNotesOutsideResults() async {
        let viewModel = makeViewModel(service: MockNoteService(notes: [
            Self.note(id: 1, content: "swift"),
        ]))
        viewModel.query = "swift"
        await viewModel.submitSearch()
        let before = viewModel.results

        viewModel.noteSaved(Self.note(id: 99, content: "unrelated"))

        XCTAssertEqual(viewModel.results, before, "search must not prepend notes that never matched")
    }

    func testTrashFromDetailRemovesResultAndDismisses() async throws {
        let note = Self.note(id: 1, content: "swift")
        let viewModel = makeViewModel(service: MockNoteService(notes: [note]))
        viewModel.query = "swift"
        await viewModel.submitSearch()
        viewModel.open(note)

        try await viewModel.trashFromDetail(id: 1)

        XCTAssertTrue(viewModel.results.isEmpty)
        XCTAssertNil(viewModel.selectedNote)
    }

    // MARK: - Helpers

    private static func note(id: Int, content: String) -> Note {
        let base = Date(timeIntervalSince1970: 1_714_000_000)
        return Note(
            id: id,
            content: content,
            createdAt: base.addingTimeInterval(TimeInterval(-id * 60)),
            updatedAt: base.addingTimeInterval(TimeInterval(-id * 60))
        )
    }
}

// MARK: - Test doubles

/// Records every list request it receives and returns an empty page.
private actor RecordingNoteService: NoteServiceProtocol {
    private(set) var requests: [NoteListRequest] = []

    func fetchNotes(_ request: NoteListRequest) async throws -> [Note] {
        requests.append(request)
        return []
    }

    func fetchNote(id: Int) async throws -> Note { throw APIError.notFound(message: nil) }
    func createNote(content: String, type: NoteType) async throws -> Note { throw APIError.notFound(message: nil) }
    func updateContent(id: Int, content: String) async throws -> Note { throw APIError.notFound(message: nil) }
    func upsert(_ request: NoteUpsertRequest) async throws -> Note { throw APIError.notFound(message: nil) }
    func setTop(id: Int, isTop: Bool) async throws -> Note { throw APIError.notFound(message: nil) }
    func setArchived(id: Int, isArchived: Bool) async throws -> Note { throw APIError.notFound(message: nil) }
    func trash(ids: [Int]) async throws {}
    func restore(ids: [Int]) async throws {}
    func delete(ids: [Int]) async throws {}
}

/// Fails the first `fetchNotes` with the given error, then serves `thenNotes`
/// filtered by the request. For retry-recovers tests.
private actor FlakyNoteService: NoteServiceProtocol {
    private var error: (any Error)?
    private let notes: [Note]

    init(error: any Error, thenNotes: [Note]) {
        self.error = error
        self.notes = thenNotes
    }

    func fetchNotes(_ request: NoteListRequest) async throws -> [Note] {
        if let error {
            self.error = nil
            throw error
        }
        return notes.filter {
            request.searchText.isEmpty || $0.content.localizedCaseInsensitiveContains(request.searchText)
        }
    }

    func fetchNote(id: Int) async throws -> Note { throw APIError.notFound(message: nil) }
    func createNote(content: String, type: NoteType) async throws -> Note { throw APIError.notFound(message: nil) }
    func updateContent(id: Int, content: String) async throws -> Note { throw APIError.notFound(message: nil) }
    func upsert(_ request: NoteUpsertRequest) async throws -> Note { throw APIError.notFound(message: nil) }
    func setTop(id: Int, isTop: Bool) async throws -> Note { throw APIError.notFound(message: nil) }
    func setArchived(id: Int, isArchived: Bool) async throws -> Note { throw APIError.notFound(message: nil) }
    func trash(ids: [Int]) async throws {}
    func restore(ids: [Int]) async throws {}
    func delete(ids: [Int]) async throws {}
}

/// Holds each `fetchNotes` call open until the test releases it by query
/// text, so response *ordering* is fully under test control. This is what
/// makes the stale-response tests deterministic instead of sleep-based.
private actor GatedNoteService: NoteServiceProtocol {
    private var pending: [String: CheckedContinuation<[Note], any Error>] = [:]

    func fetchNotes(_ request: NoteListRequest) async throws -> [Note] {
        try await withCheckedThrowingContinuation { continuation in
            pending[request.searchText] = continuation
        }
    }

    /// Spin-waits (bounded) until `count` requests are parked, so a test can
    /// sequence departures without racing the view model's task startup.
    func waitForPendingRequests(count: Int, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now + timeout
        while pending.count < count {
            guard ContinuousClock.now < deadline else {
                throw APIError.timedOut
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    func release(query: String, with notes: [Note]) {
        pending.removeValue(forKey: query)?.resume(returning: notes)
    }

    func fail(query: String, with error: any Error) {
        pending.removeValue(forKey: query)?.resume(throwing: error)
    }

    func fetchNote(id: Int) async throws -> Note { throw APIError.notFound(message: nil) }
    func createNote(content: String, type: NoteType) async throws -> Note { throw APIError.notFound(message: nil) }
    func updateContent(id: Int, content: String) async throws -> Note { throw APIError.notFound(message: nil) }
    func upsert(_ request: NoteUpsertRequest) async throws -> Note { throw APIError.notFound(message: nil) }
    func setTop(id: Int, isTop: Bool) async throws -> Note { throw APIError.notFound(message: nil) }
    func setArchived(id: Int, isArchived: Bool) async throws -> Note { throw APIError.notFound(message: nil) }
    func trash(ids: [Int]) async throws {}
    func restore(ids: [Int]) async throws {}
    func delete(ids: [Int]) async throws {}
}
