import XCTest
@testable import BlinkoApp

/// Tests for the BLI-19 additions to `HomeViewModel`: tap-to-open detail,
/// pin toggle optimistic update + rollback, single-note fetch, and the
/// compose route flag.
@MainActor
final class HomeViewModelNavigationTests: XCTestCase {

    // MARK: - Open / dismiss

    func testOpenSetsSelectedNote() {
        let note = Self.sampleNote(id: 1)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [note]))

        viewModel.open(note)

        XCTAssertEqual(viewModel.selectedNote, note)
    }

    func testDismissClearsSelectedNote() {
        let note = Self.sampleNote(id: 1)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [note]))
        viewModel.open(note)

        viewModel.dismissDetail()

        XCTAssertNil(viewModel.selectedNote)
    }

    // MARK: - Compose

    func testComposeSetsFlag() {
        let viewModel = HomeViewModel(noteService: MockNoteService())

        XCTAssertFalse(viewModel.composeRequested)

        viewModel.composeNote()

        XCTAssertTrue(viewModel.composeRequested)
    }

    // MARK: - Fetch note

    func testFetchNoteReturnsServerCopy() async throws {
        let note = Self.sampleNote(id: 1)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [note]))

        let fetched = try await viewModel.fetchNote(id: 1)

        XCTAssertEqual(fetched, note)
    }

    func testFetchNoteThrowsOnMissing() async {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: []))

        do {
            _ = try await viewModel.fetchNote(id: 999)
            XCTFail("Expected a notFound error")
        } catch APIError.notFound {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Toggle pin

    func testTogglePinFlipsLocally() async {
        let note = Self.sampleNote(id: 1, isTop: false)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [note]))
        await viewModel.loadNotes()

        await viewModel.togglePin(id: 1, isPinned: false)

        XCTAssertEqual(viewModel.notes.first?.isPinned, true)
    }

    func testTogglePinRollsBackOnFailure() async {
        let note = Self.sampleNote(id: 1, isTop: false)
        // List reads succeed; only writes fail.
        let service = MockNoteService(notes: [note], writeError: APIError.server(statusCode: 500, message: nil, code: nil))
        let viewModel = HomeViewModel(noteService: service)
        await viewModel.loadNotes()

        await viewModel.togglePin(id: 1, isPinned: false)

        XCTAssertEqual(viewModel.notes.first?.isPinned, false)
        XCTAssertTrue(viewModel.showError)
    }

    func testTogglePinNoOpWhenNoteNotInList() async {
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [Self.sampleNote(id: 1)]))
        await viewModel.loadNotes()

        let before = viewModel.notes.first?.isPinned

        await viewModel.togglePin(id: 999_999, isPinned: false)

        XCTAssertEqual(viewModel.notes.first?.isPinned, before)
    }

    // MARK: - Editor → list sync (BLI-20)

    func testNoteSavedPrependsCreatedNote() async {
        let existing = Self.sampleNote(id: 1)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [existing]))
        await viewModel.loadNotes()

        viewModel.noteSaved(Self.sampleNote(id: 2))

        XCTAssertEqual(viewModel.notes.map(\.id), [2, 1])
    }

    func testNoteSavedUpdatesEditedNoteInPlace() async {
        let notes = [Self.sampleNote(id: 1), Self.sampleNote(id: 2)]
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: notes))
        await viewModel.loadNotes()

        let originalOrder = viewModel.notes.map(\.id)
        var edited = viewModel.notes[1]
        edited.content = "edited content"
        viewModel.noteSaved(edited)

        // In-place update: same rows, same order, new content.
        XCTAssertEqual(viewModel.notes.map(\.id), originalOrder)
        XCTAssertEqual(viewModel.notes.first(where: { $0.id == edited.id })?.content, "edited content")
    }

    // MARK: - Delete from detail (BLI-20)

    func testTrashFromDetailRemovesRowAndDismisses() async throws {
        let note = Self.sampleNote(id: 1)
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: [note]))
        await viewModel.loadNotes()
        viewModel.open(note)

        try await viewModel.trashFromDetail(id: 1)

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertNil(viewModel.selectedNote)
    }

    func testTrashFromDetailRethrowsAndKeepsRowOnFailure() async {
        let note = Self.sampleNote(id: 1)
        let service = MockNoteService(notes: [note], writeError: APIError.transport("offline"))
        let viewModel = HomeViewModel(noteService: service)
        await viewModel.loadNotes()
        viewModel.open(note)

        do {
            try await viewModel.trashFromDetail(id: 1)
            XCTFail("Expected the write error to propagate")
        } catch {
            // expected — the detail view owns the error presentation.
        }

        XCTAssertEqual(viewModel.notes.map(\.id), [1])
        XCTAssertEqual(viewModel.selectedNote, note)
    }

    // MARK: - Helpers

    private static func sampleNote(id: Int, isTop: Bool = false) -> Note {
        Note(id: id, content: "Note \(id)", isTop: isTop, createdAt: Date(), updatedAt: Date())
    }
}
