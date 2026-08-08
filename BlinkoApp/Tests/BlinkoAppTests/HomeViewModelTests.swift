import XCTest
@testable import BlinkoApp

@MainActor
final class HomeViewModelTests: XCTestCase {

    // MARK: - Loading

    func testLoadNotesPopulatesNotes() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())

        await viewModel.loadNotes()

        XCTAssertFalse(viewModel.notes.isEmpty)
        XCTAssertFalse(viewModel.showError)
        XCTAssertFalse(viewModel.isLoading)
    }

    func testLoadNotesShowsErrorOnFailure() async {
        let service = MockNoteService(error: APIError.transport("offline"))
        let viewModel = HomeViewModel(noteService: service)

        await viewModel.loadNotes()

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
    }

    /// A 401 can't be recovered by retrying — there is no refresh endpoint — so
    /// the view model must signal re-authentication rather than just alerting.
    func testUnauthorizedRequestsReauthentication() async {
        let service = MockNoteService(error: APIError.unauthorized(message: nil))
        let viewModel = HomeViewModel(noteService: service)

        await viewModel.loadNotes()

        XCTAssertTrue(viewModel.requiresReauthentication)
    }

    func testTransportErrorDoesNotRequestReauthentication() async {
        let service = MockNoteService(error: APIError.transport("offline"))
        let viewModel = HomeViewModel(noteService: service)

        await viewModel.loadNotes()

        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.requiresReauthentication)
    }

    func testReloadClearsPreviousError() async {
        let viewModel = HomeViewModel(noteService: MockNoteService.failing(APIError.transport("offline")))
        await viewModel.loadNotes()
        XCTAssertTrue(viewModel.showError)

        let recovered = HomeViewModel(noteService: MockNoteService())
        await recovered.loadNotes()
        XCTAssertFalse(recovered.showError)
        XCTAssertTrue(recovered.errorMessage.isEmpty)
    }

    // MARK: - Pagination

    /// A full page means there may be more; a short page means we're done.
    /// There is no total count to check against — see docs/API-CONTRACTS.md §7.
    func testShortFirstPageMarksListExhausted() async {
        // Fixture list is smaller than one page, so it comes back short.
        let viewModel = HomeViewModel(noteService: MockNoteService())

        await viewModel.loadNotes()

        XCTAssertFalse(viewModel.syncMetadata.hasMore)
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testFullPageAllowsLoadingMore() async {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: Self.notes(count: 30)))

        await viewModel.loadNotes()

        XCTAssertEqual(viewModel.notes.count, 30)
        XCTAssertTrue(viewModel.syncMetadata.hasMore)
        XCTAssertTrue(viewModel.canLoadMore)
    }

    func testLoadMoreAppendsNextPage() async {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: Self.notes(count: 45)))

        await viewModel.loadNotes()
        XCTAssertEqual(viewModel.notes.count, 30)

        await viewModel.loadMoreNotes()

        XCTAssertEqual(viewModel.notes.count, 45)
        // Second page came back short, so the list is now exhausted.
        XCTAssertFalse(viewModel.syncMetadata.hasMore)
    }

    func testLoadMoreIsNoOpWhenExhausted() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let count = viewModel.notes.count

        await viewModel.loadMoreNotes()

        XCTAssertEqual(viewModel.notes.count, count)
    }

    func testLoadNotesResetsPaginationState() async {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: Self.notes(count: 45)))

        await viewModel.loadNotes()
        await viewModel.loadMoreNotes()
        XCTAssertEqual(viewModel.notes.count, 45)

        // A refresh replaces the list rather than appending to it.
        await viewModel.loadNotes()

        XCTAssertEqual(viewModel.notes.count, 30)
        XCTAssertEqual(viewModel.syncMetadata.page, 1)
    }

    // MARK: - Trashing

    func testTrashNoteRemovesItFromTheList() async throws {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let id = try XCTUnwrap(viewModel.notes.first?.id)
        let before = viewModel.notes.count

        await viewModel.trashNote(id: id)

        XCTAssertEqual(viewModel.notes.count, before - 1)
        XCTAssertFalse(viewModel.notes.contains { $0.id == id })
        XCTAssertFalse(viewModel.showError)
    }

    /// The removal is optimistic, so a failed call has to put the note back —
    /// otherwise the row vanishes from the UI while still existing server-side.
    /// `writeError` lets the list load succeed and only the trash call fail.
    func testFailedTrashRestoresTheNote() async throws {
        let service = MockNoteService(
            writeError: APIError.server(statusCode: 500, message: nil, code: nil)
        )
        let viewModel = HomeViewModel(noteService: service)
        await viewModel.loadNotes()

        let id = try XCTUnwrap(viewModel.notes.first?.id)
        let before = viewModel.notes

        await viewModel.trashNote(id: id)

        XCTAssertEqual(viewModel.notes.map(\.id), before.map(\.id), "note should be restored in place")
        XCTAssertTrue(viewModel.showError)
    }

    func testTrashUnknownIDDoesNothing() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let before = viewModel.notes.count

        await viewModel.trashNote(id: 999_999)

        XCTAssertEqual(viewModel.notes.count, before)
        XCTAssertFalse(viewModel.showError)
    }

    // MARK: - Helpers

    /// Builds `count` notes with distinct ids and descending timestamps.
    private static func notes(count: Int) -> [Note] {
        let base = Date(timeIntervalSince1970: 1_714_000_000)
        return (1...count).map { index in
            Note(
                id: index,
                content: "Note \(index)",
                createdAt: base.addingTimeInterval(TimeInterval(-index * 60)),
                updatedAt: base.addingTimeInterval(TimeInterval(-index * 60))
            )
        }
    }
}
