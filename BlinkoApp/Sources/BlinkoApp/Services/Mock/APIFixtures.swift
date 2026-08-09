import Foundation

/// Canned Blinko API responses, as raw JSON.
///
/// These are **wire-format samples**, not hand-built Swift values — they exist
/// so UI work can proceed before a server is reachable, and so tests exercise
/// the real decode path rather than a constructor. That distinction is the
/// whole point: a fixture built with `Note(id:content:...)` would still pass if
/// our `CodingKeys` were wrong.
///
/// Ship-safety: this lives in the main target so SwiftUI previews can use it,
/// which means it is compiled into the app. It is inert data with no call
/// sites in production code paths — `MockNoteService` is only referenced from
/// previews and tests.
///
/// Keep these faithful to what the server actually sends, quirks included.
/// See docs/API-CONTRACTS.md.
enum APIFixtures {

    /// A `POST /api/v1/note/list` response: a bare array, no envelope.
    ///
    /// Deliberately covers the shapes that have bitten us:
    /// - note 1: tags as join rows, nested two levels deep
    /// - note 2: an attachment whose `size` is a **string**, not a number
    /// - note 3: timestamps with **no fractional seconds**
    /// - note 4: a todo, pinned, with an unknown future `type` sibling
    /// - note 5: minimal payload — optional keys absent entirely
    static let noteList = """
    [
      {
        "id": 1,
        "content": "# Welcome to Blinko\\n\\nA quick capture note with #work/projects attached.",
        "type": 1,
        "isArchived": false,
        "isRecycle": false,
        "isShare": false,
        "isTop": false,
        "isReviewed": false,
        "accountId": 1,
        "sortOrder": 0,
        "createdAt": "2024-05-01T12:00:00.000Z",
        "updatedAt": "2024-05-02T09:30:00.123Z",
        "attachments": [],
        "tags": [
          {
            "noteId": 1,
            "tagId": 3,
            "tag": {
              "id": 3,
              "name": "work",
              "icon": "",
              "parent": 0,
              "accountId": 1,
              "sortOrder": 0,
              "createdAt": "2024-04-01T08:00:00.000Z",
              "updatedAt": "2024-04-01T08:00:00.000Z"
            }
          },
          {
            "noteId": 1,
            "tagId": 7,
            "tag": {
              "id": 7,
              "name": "projects",
              "icon": "📁",
              "parent": 3,
              "accountId": 1,
              "sortOrder": 1,
              "createdAt": "2024-04-01T08:05:00.000Z",
              "updatedAt": "2024-04-01T08:05:00.000Z"
            }
          }
        ]
      },
      {
        "id": 2,
        "content": "Photo from the offsite.",
        "type": 0,
        "isArchived": false,
        "isRecycle": false,
        "isShare": true,
        "isTop": false,
        "isReviewed": false,
        "accountId": 1,
        "sortOrder": 0,
        "createdAt": "2024-05-03T14:20:00.000Z",
        "updatedAt": "2024-05-03T14:20:00.000Z",
        "attachments": [
          {
            "id": 11,
            "name": "offsite.png",
            "path": "/api/file/1714746000-offsite.png",
            "size": "20480",
            "type": "image/png",
            "noteId": 2,
            "accountId": 1,
            "sortOrder": 0,
            "createdAt": "2024-05-03T14:20:00.000Z",
            "updatedAt": "2024-05-03T14:20:00.000Z"
          }
        ],
        "tags": []
      },
      {
        "id": 3,
        "content": "Timestamp landed exactly on a second, so no fractional part.",
        "type": 1,
        "isArchived": false,
        "isRecycle": false,
        "isShare": false,
        "isTop": false,
        "isReviewed": false,
        "accountId": 1,
        "sortOrder": 0,
        "createdAt": "2024-05-04T10:00:00Z",
        "updatedAt": "2024-05-04T10:00:00Z",
        "attachments": [],
        "tags": []
      },
      {
        "id": 4,
        "content": "- [ ] Ship the API contract doc\\n- [x] Recover the lost work",
        "type": 2,
        "isArchived": false,
        "isRecycle": false,
        "isShare": false,
        "isTop": true,
        "isReviewed": true,
        "accountId": 1,
        "sortOrder": 3,
        "createdAt": "2024-05-05T08:15:00.500Z",
        "updatedAt": "2024-05-06T11:45:00.000Z",
        "attachments": [],
        "tags": []
      },
      {
        "id": 5,
        "content": "Sparse payload: optional keys omitted entirely.",
        "type": 0,
        "createdAt": "2024-05-07T16:00:00.000Z",
        "updatedAt": "2024-05-07T16:00:00.000Z"
      }
    ]
    """

    /// A note carrying a `type` the client does not know about.
    ///
    /// Must decode as `.blinko` rather than throwing — one unknown enum value
    /// should never fail an entire page.
    static let noteWithUnknownType = """
    {
      "id": 99,
      "content": "Some future note type.",
      "type": 42,
      "createdAt": "2024-06-01T00:00:00.000Z",
      "updatedAt": "2024-06-01T00:00:00.000Z"
    }
    """

    /// `POST /api/v1/tags/list` — a flat array; the tree lives in `parent`.
    static let tagList = """
    [
      {
        "id": 3, "name": "work", "icon": "", "parent": 0,
        "accountId": 1, "sortOrder": 0,
        "createdAt": "2024-04-01T08:00:00.000Z",
        "updatedAt": "2024-04-01T08:00:00.000Z"
      },
      {
        "id": 7, "name": "projects", "icon": "📁", "parent": 3,
        "accountId": 1, "sortOrder": 1,
        "createdAt": "2024-04-01T08:05:00.000Z",
        "updatedAt": "2024-04-01T08:05:00.000Z"
      },
      {
        "id": 8, "name": "personal", "icon": "", "parent": 0,
        "accountId": 1, "sortOrder": 2,
        "createdAt": "2024-04-02T09:00:00.000Z",
        "updatedAt": "2024-04-02T09:00:00.000Z"
      }
    ]
    """

    /// `POST /api/v1/user/login` success.
    static let loginResponse = """
    {
      "id": 1,
      "name": "alice",
      "nickname": "Alice",
      "image": "",
      "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.mock.signature",
      "role": "superadmin",
      "loginType": "password"
    }
    """

    /// `POST /api/file/upload` — capitalized `Message`; storage keys are
    /// `filePath`/`fileName` because the route spreads
    /// `FileService.uploadFileStream`'s return value into the response.
    static let attachmentUploadResponse = """
    {
      "Message": "Success",
      "status": 200,
      "filePath": "/api/file/1714746000-offsite.png",
      "fileName": "1714746000-offsite.png",
      "type": "image/png",
      "size": 20480
    }
    """

    /// Same route, older servers: `path` instead of `filePath`, no name key.
    static let attachmentUploadResponseLegacy = """
    {
      "Message": "Success",
      "status": 200,
      "path": "/api/file/1714746000-offsite.png",
      "type": "image/png",
      "size": 20480
    }
    """

    // MARK: - Error envelopes

    /// Generated `/api/v1/*` routes: flat `{message, code}`.
    static let unauthorizedError = """
    { "message": "UNAUTHORIZED", "code": "UNAUTHORIZED" }
    """

    /// A Zod input-validation failure. `path` mixes strings and array indices.
    static let validationError = """
    {
      "message": "Input validation failed",
      "code": "BAD_REQUEST",
      "issues": [
        { "message": "Required", "path": ["content"] },
        { "message": "Expected number", "path": ["attachments", 0, "size"] }
      ]
    }
    """

    /// Hand-written file routes use `{error}` instead of `{message}`.
    static let fileRouteError = """
    { "error": "File too large" }
    """
}

extension APIFixtures {
    /// Decodes a fixture with the Blinko-configured decoder.
    ///
    /// Traps on failure by design: a fixture that does not decode is a broken
    /// fixture, and previews should fail loudly rather than render empty.
    static func decode<T: Decodable>(_ type: T.Type = T.self, from json: String) -> T {
        do {
            return try JSONDecoder.blinko.decode(T.self, from: Data(json.utf8))
        } catch {
            fatalError("Fixture failed to decode as \(T.self): \(error)")
        }
    }

    /// The sample note list, decoded. Handy for previews.
    static var sampleNotes: [Note] { decode([Note].self, from: noteList) }

    /// The sample tag list, decoded.
    static var sampleTags: [Tag] { decode([Tag].self, from: tagList) }
}
