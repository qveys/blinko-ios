import Foundation

protocol NoteServiceProtocol: Sendable {
    func fetchNotes() async throws -> [Note]
    func createNote(content: String, type: Note.NoteType) async throws -> Note
}

final class NoteService: NoteServiceProtocol {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient = URLSessionHTTPClient()) {
        self.httpClient = httpClient
    }

    func fetchNotes() async throws -> [Note] {
        let request = APIRequest(path: "/api/notes", method: .get)
        return try await httpClient.perform(request)
    }

    func createNote(content: String, type: Note.NoteType) async throws -> Note {
        let body = CreateNoteRequest(content: content, type: type)
        let request = APIRequest(path: "/api/notes", method: .post, body: body)
        return try await httpClient.perform(request)
    }
}

private struct CreateNoteRequest: Encodable {
    let content: String
    let type: Note.NoteType
}
