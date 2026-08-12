import Foundation

protocol AttachmentServiceProtocol: Sendable {
    /// Uploads raw file data to `POST /api/file/upload`.
    ///
    /// Uploading only stores the file — it is attached to nothing. To attach,
    /// pass the returned metadata to `note/upsert` via
    /// ``NoteUpsertRequest/AttachmentPayload``.
    func upload(data: Data, filename: String, mimeType: String) async throws -> AttachmentUploadResponse
}

/// Talks to Blinko's hand-written `/api/file/upload` Express route.
///
/// Unlike the generated `/api/v1/*` routes this one takes
/// `multipart/form-data`, not JSON: a single part named `file` carries the
/// bytes, and the part's filename becomes the basis of the stored name
/// (timestamped, spaces collapsed to `_`).
final class AttachmentService: AttachmentServiceProtocol {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func upload(data: Data, filename: String, mimeType: String) async throws -> AttachmentUploadResponse {
        var form = MultipartFormData()
        form.appendFile(
            fieldName: "file",
            filename: filename,
            mimeType: mimeType,
            data: data
        )
        return try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Files.upload,
                method: .post,
                rawBody: APIRequest.RawBody(
                    data: form.encoded(),
                    contentType: form.contentType
                )
            )
        )
    }
}
