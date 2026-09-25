import XCTest
@testable import BlinkoApp

/// Decoding tests against real Blinko wire formats.
///
/// These decode ``APIFixtures`` JSON rather than constructing models directly —
/// a test built from `Note(id:content:...)` would pass even with wrong
/// `CodingKeys`. Everything asserted here is a quirk that has a matching note
/// in docs/API-CONTRACTS.md.
final class ModelDecodingTests: XCTestCase {

    private let decoder = JSONDecoder.blinko

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Notes

    func testDecodesNoteList() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        XCTAssertEqual(notes.count, 5)
        XCTAssertEqual(notes[0].id, 1)
        XCTAssertEqual(notes[0].type, .note)
    }

    /// The `tags` key holds `tagsToNote` join rows with the tag nested inside.
    func testFlattensTagJoinRows() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        let tagged = notes[0]

        XCTAssertEqual(tagged.tagRelations.count, 2)
        XCTAssertEqual(tagged.tags.map(\.name), ["work", "projects"])
        XCTAssertEqual(tagged.tagRelations[0].tagId, 3)
    }

    /// Nested tags are separate rows linked by `parent`, not a slashed name.
    func testNestedTagsUseParentLinkage() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        let tags = notes[0].tags

        let work = try XCTUnwrap(tags.first { $0.name == "work" })
        let projects = try XCTUnwrap(tags.first { $0.name == "projects" })

        XCTAssertTrue(work.isRoot)
        XCTAssertFalse(projects.isRoot)
        XCTAssertEqual(projects.parent, work.id)
        // The leaf name only — never the full "work/projects" path.
        XCTAssertEqual(projects.name, "projects")
    }

    /// An unknown `type` must not fail the response.
    func testUnknownNoteTypeFallsBackToBlinko() throws {
        let note = try decode(Note.self, APIFixtures.noteWithUnknownType)
        XCTAssertEqual(note.type, .blinko)
    }

    /// Optional keys absent entirely must decode to defaults.
    func testSparseNoteDecodesWithDefaults() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        let sparse = try XCTUnwrap(notes.first { $0.id == 5 })

        XCTAssertFalse(sparse.isArchived)
        XCTAssertFalse(sparse.isTop)
        XCTAssertEqual(sparse.sortOrder, 0)
        XCTAssertTrue(sparse.attachments.isEmpty)
        XCTAssertTrue(sparse.tags.isEmpty)
        XCTAssertNil(sparse.accountId)
    }

    func testDecodesTodoAndPinnedFlags() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        let todo = try XCTUnwrap(notes.first { $0.id == 4 })

        XCTAssertEqual(todo.type, .todo)
        XCTAssertTrue(todo.isTop)
        XCTAssertTrue(todo.isReviewed)
    }

    // MARK: - Dates

    /// Postgres emits fractional seconds, except on exact-second values.
    /// Both must decode — this is why `JSONDecoder.blinko` exists.
    func testDecodesBothTimestampFormats() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)

        let fractional = try XCTUnwrap(notes.first { $0.id == 1 })
        let plain = try XCTUnwrap(notes.first { $0.id == 3 })

        XCTAssertEqual(
            fractional.updatedAt.timeIntervalSince1970,
            Date.blinkoISO8601(from: "2024-05-02T09:30:00.123Z")?.timeIntervalSince1970 ?? -1,
            accuracy: 0.001
        )
        XCTAssertEqual(
            plain.updatedAt.timeIntervalSince1970,
            Date.blinkoISO8601(from: "2024-05-04T10:00:00Z")?.timeIntervalSince1970 ?? -1,
            accuracy: 0.001
        )
    }

    /// A stock decoder fails on one of the two formats; ours must not.
    func testStockISO8601StrategyWouldFail() throws {
        let stock = JSONDecoder()
        stock.dateDecodingStrategy = .iso8601
        // `.iso8601` rejects fractional seconds, which most Blinko rows have.
        XCTAssertThrowsError(try stock.decode([Note].self, from: Data(APIFixtures.noteList.utf8)))
    }

    // MARK: - Attachments

    /// `size` is a SQL `Decimal`; drivers send it as a number *or* a string.
    func testDecodesStringEncodedAttachmentSize() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        let withFile = try XCTUnwrap(notes.first { $0.id == 2 })
        let attachment = try XCTUnwrap(withFile.attachments.first)

        XCTAssertEqual(attachment.size, 20_480)
        XCTAssertTrue(attachment.isImage)
    }

    /// `path` is server-relative and must resolve against the configured host.
    func testResolvesAttachmentURLAgainstBaseURL() throws {
        let notes = try decode([Note].self, APIFixtures.noteList)
        let attachment = try XCTUnwrap(notes.first { $0.id == 2 }?.attachments.first)
        let base = try XCTUnwrap(URL(string: "https://blinko.example.com"))

        XCTAssertEqual(
            attachment.url(relativeTo: base)?.absoluteString,
            "https://blinko.example.com/api/file/1714746000-offsite.png"
        )
    }

    /// The upload route capitalizes `Message` and spreads the storage layer's
    /// `{filePath, fileName}` into the response.
    func testDecodesAttachmentUploadResponse() throws {
        let upload = try decode(AttachmentUploadResponse.self, APIFixtures.attachmentUploadResponse)

        XCTAssertEqual(upload.message, "Success")
        XCTAssertEqual(upload.size, 20_480)
        XCTAssertEqual(upload.path, "/api/file/1714746000-offsite.png")
        XCTAssertEqual(upload.name, "1714746000-offsite.png")
    }

    /// Older servers sent `path` and no name key; the name is then derived
    /// client-side from the path's last component.
    func testDecodesLegacyAttachmentUploadResponse() throws {
        let upload = try decode(AttachmentUploadResponse.self, APIFixtures.attachmentUploadResponseLegacy)

        XCTAssertEqual(upload.path, "/api/file/1714746000-offsite.png")
        XCTAssertEqual(upload.name, "1714746000-offsite.png")
    }

    /// An upload response with neither `filePath` nor `path` is unusable.
    func testAttachmentUploadResponseRequiresAPath() {
        let json = """
        { "Message": "Success", "status": 200, "type": "image/png", "size": 1 }
        """
        XCTAssertThrowsError(
            try JSONDecoder.blinko.decode(AttachmentUploadResponse.self, from: Data(json.utf8))
        )
    }

    // MARK: - Auth

    func testDecodesLoginResponseAndStripsCredential() throws {
        let response = try decode(LoginResponse.self, APIFixtures.loginResponse)

        XCTAssertFalse(response.token.isEmpty)
        XCTAssertEqual(response.user.displayName, "Alice")
        XCTAssertTrue(response.user.isSuperAdmin)
    }

    // MARK: - Tags

    func testDecodesTagList() throws {
        let tags = try decode([Tag].self, APIFixtures.tagList)

        XCTAssertEqual(tags.count, 3)
        XCTAssertEqual(tags.filter(\.isRoot).map(\.name), ["work", "personal"])
    }
}

/// Error-envelope handling. Blinko has three spellings of "something failed";
/// all must produce a usable message.
final class APIErrorDecodingTests: XCTestCase {

    private func body(_ json: String) throws -> APIErrorBody {
        try JSONDecoder.blinko.decode(APIErrorBody.self, from: Data(json.utf8))
    }

    func testDecodesFlatErrorEnvelope() throws {
        let decoded = try body(APIFixtures.unauthorizedError)
        XCTAssertEqual(decoded.code, "UNAUTHORIZED")
        XCTAssertEqual(APIError.from(statusCode: 401, body: decoded), .unauthorized(message: "UNAUTHORIZED"))
    }

    /// File routes use `{error}` rather than `{message}`.
    func testDecodesFileRouteErrorEnvelope() throws {
        let decoded = try body(APIFixtures.fileRouteError)
        XCTAssertEqual(decoded.message, "File too large")
    }

    /// Zod `path` mixes strings and array indices; both normalize to strings.
    func testDecodesValidationIssuesWithMixedPaths() throws {
        let decoded = try body(APIFixtures.validationError)
        let detail = try XCTUnwrap(decoded.validationDetail)

        XCTAssertTrue(detail.contains("content: Required"))
        XCTAssertTrue(detail.contains("attachments.0.size: Expected number"))
    }

    func testBuildsValidationErrorFrom400WithIssues() throws {
        let decoded = try body(APIFixtures.validationError)
        guard case .validation = APIError.from(statusCode: 400, body: decoded) else {
            return XCTFail("400 with issues should map to .validation")
        }
    }

    /// A 400 *without* issues is a plain server error, not a validation error.
    func testBuildsServerErrorFrom400WithoutIssues() throws {
        let decoded = try body(APIFixtures.unauthorizedError)
        guard case .server = APIError.from(statusCode: 400, body: decoded) else {
            return XCTFail("400 without issues should map to .server")
        }
    }

    /// Retrying a 4xx just repeats the same failure; 5xx and transport are
    /// worth another attempt.
    func testRetryabilityMatchesPolicy() {
        XCTAssertTrue(APIError.transport("offline").isRetryable)
        XCTAssertTrue(APIError.server(statusCode: 500, message: nil, code: nil).isRetryable)
        XCTAssertTrue(APIError.server(statusCode: 429, message: nil, code: nil).isRetryable)
        XCTAssertTrue(APIError.server(statusCode: 408, message: nil, code: nil).isRetryable)

        XCTAssertFalse(APIError.unauthorized(message: nil).isRetryable)
        XCTAssertFalse(APIError.forbidden(message: nil).isRetryable)
        XCTAssertFalse(APIError.notFound(message: nil).isRetryable)
        XCTAssertFalse(APIError.validation(message: "bad", detail: nil).isRetryable)
        XCTAssertFalse(APIError.cancelled.isRetryable)
        XCTAssertFalse(APIError.server(statusCode: 404, message: nil, code: nil).isRetryable)
    }

    func testBackoffGrowsExponentiallyAndCaps() {
        let policy = RetryPolicy.default

        XCTAssertEqual(policy.delay(forAttempt: 0), .zero)
        XCTAssertGreaterThan(policy.delay(forAttempt: 2), policy.delay(forAttempt: 1))
        XCTAssertLessThanOrEqual(policy.delay(forAttempt: 10), policy.maxDelay)
    }
}

/// Encoding tests. `upsert` semantics depend on omitted-means-unchanged, which
/// only holds if `nil` fields stay out of the JSON.
final class RequestEncodingTests: XCTestCase {

    private func encodedKeys(_ value: some Encodable) throws -> Set<String> {
        let data = try JSONEncoder.blinko.encode(value)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return Set(object.keys)
    }

    /// A partial update must not emit keys it isn't changing — an explicit
    /// null would overwrite server-side state.
    func testPartialUpsertOmitsUntouchedFields() throws {
        let keys = try encodedKeys(NoteUpsertRequest.setTop(id: 1, isTop: true))

        XCTAssertEqual(keys, ["id", "isTop"])
        XCTAssertFalse(keys.contains("content"))
    }

    /// Creating omits `id` — that is what tells the server to insert.
    func testCreateOmitsID() throws {
        let keys = try encodedKeys(NoteUpsertRequest.create(content: "Hello", type: .note))

        XCTAssertFalse(keys.contains("id"))
        XCTAssertTrue(keys.contains("content"))
        XCTAssertTrue(keys.contains("type"))
    }

    /// The list request always sends the full body so server-side default
    /// changes can't shift behaviour underneath us.
    func testListRequestSendsFullBody() throws {
        let keys = try encodedKeys(NoteListRequest())

        for expected in ["page", "size", "orderBy", "type", "isRecycle", "searchText"] {
            XCTAssertTrue(keys.contains(expected), "list request should send \(expected)")
        }
    }

    func testRecycleBinRequestTargetsTrashedNotes() throws {
        let request = NoteListRequest.recycleBin()

        XCTAssertTrue(request.isRecycle)
        // nil, not false — the bin holds archived and unarchived notes alike.
        XCTAssertNil(request.isArchived)
    }
}
