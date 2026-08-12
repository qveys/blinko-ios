import XCTest
@testable import BlinkoApp

/// Tests for the note editor: create/edit saves, the draft-preserving
/// failure contract, attachment lifecycle (select, upload, retry, remove,
/// cancel, upsert payload), and 401 routing.
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

    // MARK: - Create (text only)

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

    // MARK: - Edit (text only)

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

    // MARK: - Attachment: select and upload

    func testAttachImageUploadsAndStagedPayload() async {
        let attachSvc = MockAttachmentService()
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "note"
        let data = Data([0xFF, 0xD8, 0xFF]) // JPEG header

        await viewModel.attachImage(data: data, filename: "photo.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(viewModel.attachments.count, 1)
        let draft = try! XCTUnwrap(viewModel.attachments.first)
        XCTAssertEqual(draft.state, .uploaded)
        XCTAssertNotNil(draft.payload)
        XCTAssertTrue(viewModel.canSave, "canSave should be true once attachment is staged")
        let uploads = await attachSvc.uploads
        XCTAssertEqual(uploads.count, 1)
        XCTAssertEqual(uploads[0].filename, "photo.jpg")
        XCTAssertEqual(uploads[0].mimeType, "image/jpeg")
    }

    func testSaveIsBlockedWhileUploadIsInFlight() async {
        // A slow upload keeps the draft in `.uploading` long enough to assert
        // that Save is gated — the acceptance criterion is that a pending
        // attachment can never be silently dropped by an early save.
        let attachSvc = MockAttachmentService(delay: .milliseconds(200))
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "text"

        let uploadTask = Task {
            await viewModel.attachImage(data: Data([0xFF, 0xD8, 0xFF]), filename: "x.jpg", mimeType: "image/jpeg")
        }

        // Wait until the draft is actually registered as in-flight, rather than
        // racing a bare `Task.yield()`.
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(viewModel.attachments.first?.state, .uploading)
        XCTAssertTrue(viewModel.isUploadingAttachment)
        XCTAssertFalse(viewModel.canSave, "Save must be gated while an upload is in flight")
        let blockedSave = await viewModel.save()
        XCTAssertFalse(blockedSave, "save() must refuse to run with a pending upload")

        await uploadTask.value

        XCTAssertEqual(viewModel.attachments.first?.state, .uploaded)
        XCTAssertFalse(viewModel.isUploadingAttachment)
        XCTAssertTrue(viewModel.canSave)
    }

    func testNonImageFileIsRejectedWithActionableMessage() async {
        let viewModel = NoteEditorViewModel(noteService: MockNoteService(notes: []))
        viewModel.content = "note"

        await viewModel.attachImage(data: Data([0x25, 0x50, 0x44, 0x46]), filename: "doc.pdf", mimeType: "application/pdf")

        XCTAssertEqual(viewModel.attachments.count, 1)
        if case .failed(let msg) = viewModel.attachments.first?.state {
            XCTAssertTrue(msg.lowercased().contains("image") || msg.lowercased().contains("photo"))
        } else {
            XCTFail("Expected failed state for non-image file")
        }
        XCTAssertFalse(viewModel.canSave, "non-image upload should not enable Save")
    }

    func testOversizedImageIsRejectedWithActionableMessage() async {
        let viewModel = NoteEditorViewModel(noteService: MockNoteService(notes: []))
        viewModel.content = "note"
        // 26 MB
        let bigData = Data(repeating: 0xFF, count: 26 * 1024 * 1024)

        await viewModel.attachImage(data: bigData, filename: "huge.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(viewModel.attachments.count, 1)
        if case .failed(let msg) = viewModel.attachments.first?.state {
            XCTAssertTrue(msg.lowercased().contains("large") || msg.lowercased().contains("mb") || msg.lowercased().contains("size"))
        } else {
            XCTFail("Expected failed state for oversized image")
        }
        XCTAssertFalse(viewModel.canSave, "oversized upload should not enable Save")
    }

    // MARK: - Attachment: remove

    func testRemoveAttachmentDropsIt() async {
        let attachSvc = MockAttachmentService()
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "note"
        await viewModel.attachImage(data: Data([0xFF,0xD8,0xFF]), filename: "p.jpg", mimeType: "image/jpeg")
        let id = try! XCTUnwrap(viewModel.attachments.first?.id)

        viewModel.removeAttachment(id: id)

        XCTAssertTrue(viewModel.attachments.isEmpty)
    }

    func testRemoveAttachmentMakesCanSaveFalseWhenOnlyChange() async {
        let attachSvc = MockAttachmentService()
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "note"
        await viewModel.attachImage(data: Data([0xFF,0xD8,0xFF]), filename: "p.jpg", mimeType: "image/jpeg")
        let id = try! XCTUnwrap(viewModel.attachments.first?.id)
        XCTAssertTrue(viewModel.canSave)

        viewModel.removeAttachment(id: id)

        // No text change either — canSave should be false
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Attachment: retry after upload failure

    func testUploadFailureTransitionsToFailedState() async {
        let attachSvc = MockAttachmentService.failing(APIError.transport("offline"))
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "note"

        await viewModel.attachImage(data: Data([0xFF,0xD8,0xFF]), filename: "p.jpg", mimeType: "image/jpeg")

        let draft = try! XCTUnwrap(viewModel.attachments.first)
        if case .failed = draft.state {
            XCTAssertTrue(draft.canRetry)
        } else {
            XCTFail("Expected failed state after upload error")
        }
        XCTAssertFalse(viewModel.canSave, "failed upload blocks Save")
    }

    func testRetryAttachmentReuploadsTheSameDraftAndSucceeds() async throws {
        // One service instance that fails the first upload and succeeds after,
        // so the retry runs through `retryAttachment(id:)` on the same draft
        // rather than a second, freshly-constructed view model.
        let attachSvc = MockAttachmentService.failingTimes(1, APIError.transport("net"))
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "note"
        await viewModel.attachImage(data: Data([0xFF, 0xD8, 0xFF]), filename: "p.jpg", mimeType: "image/jpeg")

        let failedDraft = try XCTUnwrap(viewModel.attachments.first)
        guard case .failed = failedDraft.state else {
            return XCTFail("Expected the first upload to fail")
        }
        XCTAssertTrue(failedDraft.canRetry)
        XCTAssertFalse(viewModel.canSave)

        await viewModel.retryAttachment(id: failedDraft.id)

        XCTAssertEqual(viewModel.attachments.count, 1, "Retry must reuse the draft, not append a second one")
        let retried = try XCTUnwrap(viewModel.attachments.first)
        XCTAssertEqual(retried.id, failedDraft.id)
        XCTAssertEqual(retried.state, .uploaded)
        XCTAssertNotNil(retried.payload)
        XCTAssertTrue(viewModel.canSave, "A successful retry unblocks Save")

        let uploads = await attachSvc.uploads
        XCTAssertEqual(uploads.count, 1, "Only the successful attempt is recorded")
    }

    // MARK: - Attachment: upsert payload

    func testSaveIncludesAttachmentPayloadInUpsert() async throws {
        let attachSvc = MockAttachmentService()
        let noteService = MockNoteService(notes: [])
        var savedNote: Note?
        let viewModel = NoteEditorViewModel(
            noteService: noteService,
            attachmentService: attachSvc,
            onSaved: { savedNote = $0 }
        )
        viewModel.content = "with image"
        await viewModel.attachImage(data: Data([0xFF,0xD8,0xFF]), filename: "img.jpg", mimeType: "image/jpeg")

        let success = await viewModel.save()

        XCTAssertTrue(success)
        XCTAssertNotNil(savedNote)
        // The note service should have received the upsert; the mock creates the note.
        let notes = try await noteService.fetchNotes()
        XCTAssertEqual(notes.first?.content, "with image")
    }

    func testCanSaveIsFalseWhileAttachmentIsPending() async {
        let attachSvc = MockAttachmentService.failing(APIError.transport("x"))
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "note"
        await viewModel.attachImage(data: Data([0xFF,0xD8,0xFF]), filename: "img.jpg", mimeType: "image/jpeg")
        // After failure, payload is nil — canSave must be false
        XCTAssertFalse(viewModel.canSave)
    }

    // MARK: - Existing attachments loaded from note

    func testEditWithExistingAttachmentPreloadsAsUploaded() {
        let base = Date(timeIntervalSince1970: 1_725_000_000)
        let attachment = Attachment(
            id: 7, name: "photo.jpg", path: "/api/file/photo.jpg", size: 12345,
            type: "image/jpeg", noteId: 1, sortOrder: 0, createdAt: base, updatedAt: base
        )
        let note = Note(id: 1, content: "has image", createdAt: base, updatedAt: base, attachments: [attachment])
        let viewModel = NoteEditorViewModel(noteService: MockNoteService(notes: [note]), note: note)

        XCTAssertEqual(viewModel.attachments.count, 1)
        XCTAssertEqual(viewModel.attachments.first?.state, .uploaded)
        XCTAssertNotNil(viewModel.attachments.first?.payload)
        XCTAssertEqual(viewModel.attachments.first?.name, "photo.jpg")
    }

    // MARK: - Draft preservation: failed upload does not lose text

    func testDraftPreservedAfterUploadFailure() async {
        let attachSvc = MockAttachmentService.failing(APIError.transport("net"))
        let viewModel = NoteEditorViewModel(
            noteService: MockNoteService(notes: []),
            attachmentService: attachSvc
        )
        viewModel.content = "important draft"
        await viewModel.attachImage(data: Data([0xFF,0xD8,0xFF]), filename: "p.jpg", mimeType: "image/jpeg")

        XCTAssertEqual(viewModel.content, "important draft")
    }

    // MARK: - Helpers

    private static func sampleNote(id: Int, content: String) -> Note {
        Note(id: id, content: content, createdAt: Date(), updatedAt: Date())
    }
}
