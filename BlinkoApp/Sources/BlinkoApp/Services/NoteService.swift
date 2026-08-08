import Foundation

protocol NoteServiceProtocol: Sendable {
    func fetchNotes(_ request: NoteListRequest) async throws -> [Note]
    func fetchNote(id: Int) async throws -> Note
    func createNote(content: String, type: NoteType) async throws -> Note
    func updateContent(id: Int, content: String) async throws -> Note
    func upsert(_ request: NoteUpsertRequest) async throws -> Note
    func setTop(id: Int, isTop: Bool) async throws -> Note
    func setArchived(id: Int, isArchived: Bool) async throws -> Note
    /// Soft-deletes into the recycle bin.
    func trash(ids: [Int]) async throws
    /// Restores notes out of the recycle bin.
    func restore(ids: [Int]) async throws
    /// Permanently deletes. Not reversible.
    func delete(ids: [Int]) async throws
}

extension NoteServiceProtocol {
    /// Convenience for the common "first page of active notes" case.
    func fetchNotes() async throws -> [Note] {
        try await fetchNotes(NoteListRequest())
    }
}

/// Talks to Blinko's `/api/v1/note/*` endpoints.
///
/// Note that reads are `POST` here — that is Blinko's REST shape, not a
/// mistake: tRPC queries with input objects map onto POST bodies.
final class NoteService: NoteServiceProtocol {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchNotes(_ request: NoteListRequest) async throws -> [Note] {
        try await httpClient.perform(
            APIRequest(path: BlinkoAPI.Notes.list, method: .post, body: request)
        )
    }

    func fetchNote(id: Int) async throws -> Note {
        try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Notes.detail,
                method: .post,
                body: NoteDetailRequest(id: id)
            )
        )
    }

    func createNote(content: String, type: NoteType = .blinko) async throws -> Note {
        try await upsert(.create(content: content, type: type))
    }

    func updateContent(id: Int, content: String) async throws -> Note {
        try await upsert(.updateContent(id: id, content: content))
    }

    func upsert(_ request: NoteUpsertRequest) async throws -> Note {
        try await httpClient.perform(
            APIRequest(path: BlinkoAPI.Notes.upsert, method: .post, body: request)
        )
    }

    func setTop(id: Int, isTop: Bool) async throws -> Note {
        try await upsert(.setTop(id: id, isTop: isTop))
    }

    func setArchived(id: Int, isArchived: Bool) async throws -> Note {
        try await upsert(.setArchived(id: id, isArchived: isArchived))
    }

    func trash(ids: [Int]) async throws {
        try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Notes.batchTrash,
                method: .post,
                body: NoteBatchRequest(ids: ids)
            )
        )
    }

    func restore(ids: [Int]) async throws {
        try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Notes.batchUpdate,
                method: .post,
                body: NoteBatchUpdateRequest.restore(ids: ids)
            )
        )
    }

    func delete(ids: [Int]) async throws {
        try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Notes.batchDelete,
                method: .post,
                body: NoteBatchRequest(ids: ids)
            )
        )
    }
}
