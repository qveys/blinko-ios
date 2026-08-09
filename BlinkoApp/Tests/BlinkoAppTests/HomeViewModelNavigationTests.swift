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

    // MARK: - Helpers

    private static func sampleNote(id: Int, isTop: Bool = false) -> Note {
        Note(id: id, content: "Note \(id)", isTop: isTop, createdAt: Date(), updatedAt: Date())
    }
}
