import Foundation

/// Request body for `POST /api/v1/note/list`.
///
/// Every field has a server-side default, but we always send the full body so
/// behaviour does not shift if those defaults change.
struct NoteListRequest: Encodable, Sendable {
    var tagId: Int?
    var page: Int
    var size: Int
    var orderBy: OrderDirection
    /// `NoteType.rawValue`, or `NoteType.any` (-1) for no type filter.
    var type: Int
    var isArchived: Bool?
    var isShare: Bool?
    var isRecycle: Bool
    var searchText: String
    var withoutTag: Bool
    var withFile: Bool
    var withLink: Bool
    var hasTodo: Bool
    /// Routes the query through the server's AI/vector search instead of a
    /// plain `LIKE` match. Requires AI to be configured on the instance.
    var isUseAiQuery: Bool

    enum OrderDirection: String, Encodable, Sendable, Equatable {
        case ascending = "asc"
        case descending = "desc"
    }

    init(
        page: Int = 1,
        size: Int = SyncMetadata.defaultPageSize,
        type: NoteType? = nil,
        tagId: Int? = nil,
        searchText: String = "",
        orderBy: OrderDirection = .descending,
        isArchived: Bool? = false,
        isShare: Bool? = nil,
        isRecycle: Bool = false,
        withoutTag: Bool = false,
        withFile: Bool = false,
        withLink: Bool = false,
        hasTodo: Bool = false,
        isUseAiQuery: Bool = false
    ) {
        self.page = page
        self.size = size
        self.type = type?.rawValue ?? NoteType.any
        self.tagId = tagId
        self.searchText = searchText
        self.orderBy = orderBy
        self.isArchived = isArchived
        self.isShare = isShare
        self.isRecycle = isRecycle
        self.withoutTag = withoutTag
        self.withFile = withFile
        self.withLink = withLink
        self.hasTodo = hasTodo
        self.isUseAiQuery = isUseAiQuery
    }

    /// The recycle bin: trashed notes only.
    static func recycleBin(page: Int = 1) -> NoteListRequest {
        NoteListRequest(page: page, isArchived: nil, isRecycle: true)
    }

    /// Archived notes only.
    static func archived(page: Int = 1) -> NoteListRequest {
        NoteListRequest(page: page, isArchived: true)
    }
}

/// Request body for `POST /api/v1/note/upsert`.
///
/// **Null means "leave unchanged", not "set to null".** The server defaults
/// every optional flag to `null` and only writes a column when the value is
/// non-null, so a partial update must omit (or null) the fields it isn't
/// touching. `Encodable` synthesis skips `nil` optionals, which gives us
/// exactly that behaviour — do not add a custom encoder that emits explicit
/// nulls, and do not make these non-optional.
///
/// Omitting `id` creates a note; supplying it updates that note.
struct NoteUpsertRequest: Encodable, Sendable {
    var id: Int?
    var content: String?
    /// `NoteType.rawValue`; omitted entirely to leave the type unchanged.
    var type: Int?
    var isArchived: Bool?
    var isTop: Bool?
    var isShare: Bool?
    var isRecycle: Bool?
    /// Attachments to associate. Must already be uploaded via
    /// `POST /api/file/upload` — see ``AttachmentUploadResponse``.
    var attachments: [AttachmentPayload]?
    /// IDs of notes this note references.
    var references: [Int]?

    /// The attachment shape `upsert` accepts: metadata only, no `id`.
    struct AttachmentPayload: Encodable, Sendable, Equatable {
        var name: String
        var path: String
        var size: Int64
        var type: String

        init(name: String, path: String, size: Int64, type: String) {
            self.name = name
            self.path = path
            self.size = size
            self.type = type
        }

        init(_ attachment: Attachment) {
            self.init(
                name: attachment.name,
                path: attachment.path,
                size: attachment.size,
                type: attachment.type
            )
        }

        init(_ upload: AttachmentUploadResponse) {
            self.init(
                name: upload.name,
                path: upload.path,
                size: upload.size,
                type: upload.type
            )
        }
    }

    /// Creates a new note.
    static func create(
        content: String,
        type: NoteType = .blinko,
        attachments: [AttachmentPayload] = [],
        references: [Int] = []
    ) -> NoteUpsertRequest {
        NoteUpsertRequest(
            content: content,
            type: type.rawValue,
            attachments: attachments.isEmpty ? nil : attachments,
            references: references.isEmpty ? nil : references
        )
    }

    /// Updates the content and optionally replaces the attachment list.
    static func updateContent(
        id: Int,
        content: String,
        attachments: [AttachmentPayload]? = nil
    ) -> NoteUpsertRequest {
        NoteUpsertRequest(id: id, content: content, attachments: attachments)
    }

    /// Toggles the pinned state, leaving everything else untouched.
    static func setTop(id: Int, isTop: Bool) -> NoteUpsertRequest {
        NoteUpsertRequest(id: id, isTop: isTop)
    }

    /// Moves a note to (or out of) the archive.
    static func setArchived(id: Int, isArchived: Bool) -> NoteUpsertRequest {
        NoteUpsertRequest(id: id, isArchived: isArchived)
    }

    /// Moves a note to (or out of) the recycle bin. This is a soft delete;
    /// permanent deletion goes through `/v1/note/batch-delete`.
    static func setRecycled(id: Int, isRecycle: Bool) -> NoteUpsertRequest {
        NoteUpsertRequest(id: id, isRecycle: isRecycle)
    }
}

/// Request body for `POST /api/v1/note/detail`.
struct NoteDetailRequest: Encodable, Sendable {
    var id: Int
}

/// Request body for `POST /api/v1/note/batch-trash` and
/// `POST /api/v1/note/batch-delete`, both of which take only `ids`.
///
/// `batch-trash` soft-deletes (sets `isRecycle = true`) and fires the server's
/// delete webhook. `batch-delete` is permanent and fails the whole call unless
/// you own every listed note. To *restore* from the bin, use
/// ``NoteBatchUpdateRequest/restore(ids:)`` — trash is one-way.
struct NoteBatchRequest: Encodable, Sendable {
    var ids: [Int]
}

/// Request body for `POST /api/v1/note/batch-update`.
///
/// Uses the same "sentinel means unchanged" convention as upsert, but note the
/// sentinel differs per field: `type` is skipped when it is `-1`, while the
/// booleans are skipped when null. Encoding omits nil optionals, so the server
/// applies its own null default and leaves the column alone.
struct NoteBatchUpdateRequest: Encodable, Sendable {
    var ids: [Int]
    /// `NoteType.rawValue`, or `NoteType.any` (-1) to leave the type unchanged.
    var type: Int
    var isArchived: Bool?
    var isRecycle: Bool?

    init(ids: [Int], type: NoteType? = nil, isArchived: Bool? = nil, isRecycle: Bool? = nil) {
        self.ids = ids
        self.type = type?.rawValue ?? NoteType.any
        self.isArchived = isArchived
        self.isRecycle = isRecycle
    }

    /// Restores notes out of the recycle bin.
    static func restore(ids: [Int]) -> NoteBatchUpdateRequest {
        NoteBatchUpdateRequest(ids: ids, isRecycle: false)
    }

    /// Archives or unarchives notes in bulk.
    static func setArchived(ids: [Int], isArchived: Bool) -> NoteBatchUpdateRequest {
        NoteBatchUpdateRequest(ids: ids, isArchived: isArchived)
    }
}
