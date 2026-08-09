import XCTest
@testable import BlinkoApp

/// Tests for the BLI-20 editor: create/edit saves, the draft-preserving
/// failure contract, save gating, and 401 routing.
@MainActor
final class NoteEditorViewModelTests: XCTestCase {
    // MARK: - Mode

    func testCreateModeWithoutNote() {
        let viewModel = NoteEditorViewModel(noteService: MockNoteService())
        XCTAssertEqual(viewModel.mode, .create)
        XCTAssertEqual(viewModel.content, "")
    }

    func testEditModePrefillsContent() {
        let note = Self.sampleNote(id: 3, content: "# Hello\n\nBody")
        let viewModel = NoteEditorViewModel(noteService: MockNoteService(notes: [note]), note: note)
        XCTAssertEqual(viewModel.mode, .edit(id: 3))
        XCTAssertEqual(viewModel.content, "# Hello\n\nBody")
    }

    // MARK: - Save gating

    func testCannotSaveEmptyOrWhitespaceDraft() {
        let viewModel = NoteEditorViewModel(noteService: MockNoteService())
        XCTAssertFalse(viewModel.canSave)
        viewModel.content = "   \n  "
        XCTAssertFalse(viewModel.canSave)
        viewModel.content = "text"
        XCTAssertTrue(viewModel.canSave)
    }

    func testCannotSaveUnchangedContent() {
        let note = Self.sampleNote(id: 1, content: "same")
        let viewModel = NoteEditorViewModel(noteService: MockNoteService(notes: [note]), note: note)
        XCTAssertFalse(viewModel.canSave)
        viewModel.content = "different"
        XCTAssertTrue(viewModel.canSave)
    }

    func testHasUnsavedChangesTracksDraft() {
        let viewModel = NoteEditorViewModel(noteService: MockNoteService())
        XCTAssertFalse(viewModel.hasUnsavedChanges)
        viewModel.content = "draft"
        XCTAssertTrue(viewModel.hasUnsavedChanges)
    }

    // MARK: - Create

    func testCreatePersistsNoteAndReportsIt() async throws {
        let service = MockNoteService(notes: [])
        var savedNote: Note?
        let viewModel = NoteEditorViewModel(noteService: service) { savedNote = $0 }
        viewModel.content = "# New note\n\nBody"

        let success = await viewModel.save()

        XCTAssertTrue(success)
        XCTAssertEqual(savedNote?.content, "# New note\n\nBody")
        let persisted = try await service.fetchNotes()
        XCTAssertEqual(persisted.first?.content, "# New note\n\nBody")
    }

    // MARK: - Edit

    func testEditUpdatesExistingNote() async throws {
        let note = Self.sampleNote(id: 5, content: "old")
        let service = MockNoteService(notes: [note])
        var savedNote: Note?
        let viewModel = NoteEditorViewModel(noteService: service, note: note) { savedNote = $0 }
        viewModel.content = "new content"

        let success = await viewModel.save()

        XCTAssertTrue(success)
        XCTAssertEqual(savedNote?.id, 5)
        let fetched = try await service.fetchNote(id: 5)
        XCTAssertEqual(fetched.content, "new content")
    }

    // MARK: - Failure: draft preserved, recoverable

    func testFailedSavePreservesDraftAndShowsError() async {
        let service = MockNoteService(writeError: APIError.transport("offline"))
        var savedNote: Note?
        let viewModel = NoteEditorViewModel(noteService: service) { savedNote = $0 }
        viewModel.content = "my precious draft"

        let success = await viewModel.save()

        XCTAssertFalse(success)
        XCTAssertEqual(viewModel.content, "my precious draft")
        XCTAssertTrue(viewModel.showError)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
        XCTAssertNil(savedNote)
    }

    func testRetryAfterFailureSucceedsWithSameDraft() async {
        // First save fails; the retry hits a healthy service with the intact draft.
        let failing = NoteEditorViewModel(noteService: MockNoteService(writeError: APIError.timedOut))
        failing.content = "draft"
        _ = await failing.save()
        XCTAssertEqual(failing.content, "draft")

        let healthy = MockNoteService(notes: [])
        let viewModel = NoteEditorViewModel(noteService: healthy)
        viewModel.content = failing.content
        let success = await viewModel.save()
        XCTAssertTrue(success)
    }

    func testUnauthorizedRoutesToReauthNotGenericError() async {
        let service = MockNoteService(writeError: APIError.unauthorized(message: nil))
        let viewModel = NoteEditorViewModel(noteService: service)
        viewModel.content = "draft"

        let success = await viewModel.save()

        XCTAssertFalse(success)
        XCTAssertTrue(viewModel.requiresReauthentication)
        XCTAssertFalse(viewModel.showError)
        XCTAssertEqual(viewModel.content, "draft")
    }

    // MARK: - Helpers

    private static func sampleNote(id: Int, content: String) -> Note {
        Note(id: id, content: content, createdAt: Date(), updatedAt: Date())
    }
}
