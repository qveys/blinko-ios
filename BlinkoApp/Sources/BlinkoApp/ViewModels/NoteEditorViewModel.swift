import Combine
import Foundation

/// Drives the note editor for both create (`note == nil`) and edit flows.
///
/// Failure handling is deliberately draft-preserving: a failed save or upload
/// leaves `content` untouched and raises recoverable UI state, so a network drop
/// never eats the user's text.
@MainActor
final class NoteEditorViewModel: ObservableObject {
    enum Mode: Equatable {
        case create
        /// Editing an existing note; holds the id being updated.
        case edit(id: Int)
    }

    enum AttachmentState: Equatable, Sendable {
        case uploading
        case uploaded
        case failed(message: String)
    }

    struct AttachmentDraft: Identifiable, Equatable, Sendable {
        let id: UUID
        var name: String
        var mimeType: String
        var byteCount: Int
        var state: AttachmentState
        var payload: NoteUpsertRequest.AttachmentPayload?
        var retryData: Data?

        var canRetry: Bool {
            if case .failed = state { return retryData != nil }
            return false
        }
    }

    @Published var content: String
    @Published private(set) var attachments: [AttachmentDraft]
    @Published private(set) var isSaving = false
    @Published private(set) var isUploadingAttachment = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""
    /// Mirrors `HomeViewModel`: a 401 routes to re-auth instead of the
    /// generic error alert.
    @Published var requiresReauthentication = false

    let mode: Mode
    private let noteType: NoteType
    private let originalContent: String
    private let originalAttachmentPayloads: [NoteUpsertRequest.AttachmentPayload]
    private let noteService: any NoteServiceProtocol
    private let attachmentService: any AttachmentServiceProtocol
    /// Called with the server's copy after a successful save, so the owning
    /// screen can refresh its list/detail without another round-trip.
    private let onSaved: (Note) -> Void

    init(
        noteService: any NoteServiceProtocol,
        attachmentService: any AttachmentServiceProtocol = MockAttachmentService(),
        note: Note? = nil,
        noteType: NoteType = .blinko,
        onSaved: @escaping (Note) -> Void = { _ in }
    ) {
        self.noteService = noteService
        self.attachmentService = attachmentService
        self.mode = note.map { .edit(id: $0.id) } ?? .create
        self.noteType = note?.type ?? noteType
        self.content = note?.content ?? ""
        self.originalContent = note?.content ?? ""
        self.originalAttachmentPayloads = note?.attachments.map(NoteUpsertRequest.AttachmentPayload.init) ?? []
        self.attachments = note?.attachments.map { attachment in
            AttachmentDraft(
                id: UUID(),
                name: attachment.name,
                mimeType: attachment.type,
                byteCount: Int(attachment.size),
                state: .uploaded,
                payload: NoteUpsertRequest.AttachmentPayload(attachment),
                retryData: nil
            )
        } ?? []
        self.onSaved = onSaved
    }

    /// A save is allowed once there is real text, every attachment is uploaded,
    /// and either text or attachments differ from what the server already has.
    var canSave: Bool {
        !isSaving
            && !isUploadingAttachment
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !attachments.contains { $0.payload == nil }
            && (content != originalContent || attachmentPayloads != originalAttachmentPayloads)
    }

    /// `true` when leaving now would lose typed text or newly selected files.
    var hasUnsavedChanges: Bool {
        (content != originalContent
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            || attachmentPayloads != originalAttachmentPayloads
            || attachments.contains { $0.payload == nil }
    }

    var attachmentHint: String? {
        if attachments.contains(where: { if case .failed = $0.state { return true }; return false }) {
            return "One image failed to upload. Retry or remove it before saving."
        }
        if isUploadingAttachment { return "Uploading image…" }
        return nil
    }

    /// Uploads a selected photo-library image and stages the returned attachment
    /// metadata for the eventual note upsert.
    func attachImage(data: Data, filename: String, mimeType: String?) async {
        let resolvedMimeType = mimeType ?? "application/octet-stream"
        guard resolvedMimeType.hasPrefix("image/") else {
            addFailedAttachment(
                name: filename,
                mimeType: resolvedMimeType,
                byteCount: data.count,
                data: data,
                message: "Choose an image file from your photo library."
            )
            return
        }
        guard data.count <= Self.maxImageBytes else {
            addFailedAttachment(
                name: filename,
                mimeType: resolvedMimeType,
                byteCount: data.count,
                data: data,
                message: "This image is too large. Choose an image under 25 MB."
            )
            return
        }

        let id = UUID()
        attachments.append(
            AttachmentDraft(
                id: id,
                name: filename,
                mimeType: resolvedMimeType,
                byteCount: data.count,
                state: .uploading,
                payload: nil,
                retryData: data
            )
        )
        await uploadAttachment(id: id, data: data, filename: filename, mimeType: resolvedMimeType)
    }

    func retryAttachment(id: UUID) async {
        guard let attachment = attachments.first(where: { $0.id == id }),
              let data = attachment.retryData else { return }
        await uploadAttachment(id: id, data: data, filename: attachment.name, mimeType: attachment.mimeType)
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
    }

    /// Persists the draft. Returns `true` on success so the view knows to
    /// dismiss; on failure the draft stays in `content` for retry.
    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: Note
            switch mode {
            case .create:
                saved = try await noteService.upsert(.create(content: content, type: noteType, attachments: attachmentPayloads))
            case .edit(let id):
                saved = try await noteService.upsert(.updateContent(id: id, content: content, attachments: attachmentPayloads))
            }
            clearError()
            onSaved(saved)
            return true
        } catch {
            present(error)
            return false
        }
    }

    private var attachmentPayloads: [NoteUpsertRequest.AttachmentPayload] {
        attachments.compactMap(\.payload)
    }

    private func uploadAttachment(id: UUID, data: Data, filename: String, mimeType: String) async {
        updateAttachment(id: id) { draft in
            draft.state = .uploading
            draft.payload = nil
        }
        isUploadingAttachment = true
        defer { isUploadingAttachment = attachments.contains { $0.state == .uploading } }

        do {
            let upload = try await attachmentService.upload(data: data, filename: filename, mimeType: mimeType)
            updateAttachment(id: id) { draft in
                draft.name = upload.name
                draft.mimeType = upload.type
                draft.byteCount = Int(upload.size)
                draft.state = .uploaded
                draft.payload = NoteUpsertRequest.AttachmentPayload(upload)
                draft.retryData = nil
            }
            clearError()
        } catch {
            updateAttachment(id: id) { draft in
                draft.state = .failed(message: error.localizedDescription)
                draft.retryData = data
            }
        }
    }

    private func addFailedAttachment(name: String, mimeType: String, byteCount: Int, data: Data, message: String) {
        attachments.append(
            AttachmentDraft(
                id: UUID(),
                name: name,
                mimeType: mimeType,
                byteCount: byteCount,
                state: .failed(message: message),
                payload: nil,
                retryData: data
            )
        )
    }

    private func updateAttachment(id: UUID, _ update: (inout AttachmentDraft) -> Void) {
        guard let index = attachments.firstIndex(where: { $0.id == id }) else { return }
        update(&attachments[index])
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        if case APIError.unauthorized = error {
            requiresReauthentication = true
        } else {
            showError = true
        }
    }

    private func clearError() {
        errorMessage = ""
        showError = false
    }

    private static let maxImageBytes = 25 * 1024 * 1024
}
