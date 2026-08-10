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

    // MARK: - Pinning (BLI-40)

    /// A successful pin floats the row to the top of the list, above the
    /// other unpinned rows, matching Blinko web's pinned-first ordering.
    func testTogglePinMovesNoteToTop() async throws {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: Self.notes(count: 5)))
        await viewModel.loadNotes()
        let id = try XCTUnwrap(viewModel.notes.last?.id)

        await viewModel.togglePin(id: id, isPinned: false)

        XCTAssertEqual(viewModel.notes.first?.id, id)
        XCTAssertTrue(viewModel.notes[0].isTop)
        XCTAssertFalse(viewModel.showError)
    }

    /// Pinning a second note keeps both pinned rows ahead of the unpinned
    /// ones and preserves recency order within the pinned group.
    func testPinnedSortIsStableWithinGroups() async throws {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: Self.notes(count: 5)))
        await viewModel.loadNotes()
        let firstPinned = viewModel.notes[3].id
        let secondPinned = viewModel.notes[4].id

        await viewModel.togglePin(id: firstPinned, isPinned: false)
        await viewModel.togglePin(id: secondPinned, isPinned: false)

        XCTAssertEqual(viewModel.notes.prefix(2).map(\.id), [firstPinned, secondPinned])
        XCTAssertTrue(viewModel.notes.prefix(2).allSatisfy(\.isTop))
    }

    /// A failed pin rolls the flag back and never reorders the list.
    func testFailedTogglePinRollsBackAndKeepsOrder() async throws {
        let service = MockNoteService(
            notes: Self.notes(count: 5),
            writeError: APIError.server(statusCode: 500, message: nil, code: nil)
        )
        let viewModel = HomeViewModel(noteService: service)
        await viewModel.loadNotes()
        let before = viewModel.notes.map(\.id)
        let id = try XCTUnwrap(viewModel.notes.last?.id)

        await viewModel.togglePin(id: id, isPinned: false)

        XCTAssertEqual(viewModel.notes.map(\.id), before, "order must not change on failure")
        XCTAssertFalse(viewModel.notes.last!.isTop, "flag must roll back")
        XCTAssertTrue(viewModel.showError)
    }

    // MARK: - Archiving (BLI-40)

    /// Archiving from the active list removes the row — archived notes are
    /// not part of the default scope.
    func testToggleArchiveRemovesNoteFromActiveList() async throws {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let id = try XCTUnwrap(viewModel.notes.first?.id)
        let before = viewModel.notes.count

        await viewModel.toggleArchive(id: id)

        XCTAssertEqual(viewModel.notes.count, before - 1)
        XCTAssertFalse(viewModel.notes.contains { $0.id == id })
        XCTAssertFalse(viewModel.showError)
    }

    /// A failed archive puts the row back in its original position with the
    /// original flag, and surfaces the error alert.
    func testFailedToggleArchiveRestoresTheNote() async throws {
        let service = MockNoteService(
            writeError: APIError.server(statusCode: 500, message: nil, code: nil)
        )
        let viewModel = HomeViewModel(noteService: service)
        await viewModel.loadNotes()
        let before = viewModel.notes.map(\.id)
        let id = try XCTUnwrap(viewModel.notes.first?.id)

        await viewModel.toggleArchive(id: id)

        XCTAssertEqual(viewModel.notes.map(\.id), before, "note should be restored in place")
        XCTAssertFalse(viewModel.notes.first!.isArchived, "flag must roll back")
        XCTAssertTrue(viewModel.showError)
    }

    func testToggleArchiveUnknownIDDoesNothing() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let before = viewModel.notes.count

        await viewModel.toggleArchive(id: 999_999)

        XCTAssertEqual(viewModel.notes.count, before)
        XCTAssertFalse(viewModel.showError)
    }

    // MARK: - Archived filter (BLI-40)

    /// Switching to the archived scope refetches with `isArchived == true`,
    /// so only archived notes are shown.
    func testShowArchivedFetchesOnlyArchivedNotes() async {
        let base = Date(timeIntervalSince1970: 1_714_000_000)
        // Distinct ids across the two groups.
        let archived = (0..<2).map {
            Note(id: 100 + $0, content: "Archived \($0)", isArchived: true, createdAt: base, updatedAt: base)
        }
        let seed = archived + Self.notes(count: 3)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: seed))

        await viewModel.loadNotes()
        XCTAssertEqual(viewModel.notes.count, 3, "default scope hides archived notes")

        await viewModel.setShowsArchived(true)

        XCTAssertTrue(viewModel.showsArchived)
        XCTAssertEqual(viewModel.notes.count, 2)
        XCTAssertTrue(viewModel.notes.allSatisfy(\.isArchived))
    }

    /// Unarchiving inside the archived scope removes the row from that scope.
    func testUnarchiveRemovesNoteFromArchivedList() async throws {
        let base = Date(timeIntervalSince1970: 1_714_000_000)
        let archivedNote = Note(id: 1, content: "Archived", isArchived: true, createdAt: base, updatedAt: base)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [archivedNote]))
        await viewModel.setShowsArchived(true)
        XCTAssertEqual(viewModel.notes.count, 1)

        await viewModel.toggleArchive(id: 1)

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertFalse(viewModel.showError)
    }

    /// Re-setting the same scope must not refetch (it would clobber optimistic
    /// state under the user's finger).
    func testSetShowsArchivedIsNoOpForSameValue() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let before = viewModel.notes.map(\.id)

        await viewModel.setShowsArchived(false)

        XCTAssertEqual(viewModel.notes.map(\.id), before)
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
