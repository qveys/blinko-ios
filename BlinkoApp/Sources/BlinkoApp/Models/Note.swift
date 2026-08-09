import Foundation

/// The kind of a note, as stored by the Blinko backend.
///
/// The server persists this as an `Int` (`notes.type`), matching the
/// `NoteType` enum in Blinko's `shared/lib/types.ts`. `-1` is not a stored
/// value — it is the wildcard the list endpoint uses to mean "any type".
enum NoteType: Int, Codable, Sendable, CaseIterable {
    case blinko = 0
    case note = 1
    case todo = 2

    /// Wildcard accepted by `/v1/note/list` and `/v1/note/upsert` to mean
    /// "no type filter" / "leave type unchanged".
    static let any = -1
}

/// A note as returned by the Blinko API.
///
/// Field names mirror `model notes` in Blinko's `prisma/schema.prisma` so the
/// default `CodingKeys` decode the wire format directly.
struct Note: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: Int
    var content: String
    var type: NoteType
    var isArchived: Bool
    var isRecycle: Bool
    var isShare: Bool
    var isTop: Bool
    var isReviewed: Bool
    var accountId: Int?
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    /// Present on list/detail responses. Absent on some write responses.
    var attachments: [Attachment]
    /// The join rows carry the tag payload; use ``tags`` for the flattened list.
    var tagRelations: [TagRelation]

    enum CodingKeys: String, CodingKey {
        case id, content, type, isArchived, isRecycle, isShare, isTop
        case isReviewed, accountId, sortOrder, createdAt, updatedAt
        case attachments
        case tagRelations = "tags"
    }

    /// Tags attached to this note, flattened out of the join rows.
    var tags: [Tag] { tagRelations.map(\.tag) }

    init(
        id: Int,
        content: String,
        type: NoteType = .blinko,
        isArchived: Bool = false,
        isRecycle: Bool = false,
        isShare: Bool = false,
        isTop: Bool = false,
        isReviewed: Bool = false,
        accountId: Int? = nil,
        sortOrder: Int = 0,
        createdAt: Date,
        updatedAt: Date,
        attachments: [Attachment] = [],
        tagRelations: [TagRelation] = []
    ) {
        self.id = id
        self.content = content
        self.type = type
        self.isArchived = isArchived
        self.isRecycle = isRecycle
        self.isShare = isShare
        self.isTop = isTop
        self.isReviewed = isReviewed
        self.accountId = accountId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.attachments = attachments
        self.tagRelations = tagRelations
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        // Unknown/future type integers decode as `.blinko` rather than failing
        // the whole response, matching the server's own `toNoteTypeEnum` fallback.
        let rawType = try container.decodeIfPresent(Int.self, forKey: .type) ?? 0
        type = NoteType(rawValue: rawType) ?? .blinko
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        isRecycle = try container.decodeIfPresent(Bool.self, forKey: .isRecycle) ?? false
        isShare = try container.decodeIfPresent(Bool.self, forKey: .isShare) ?? false
        isTop = try container.decodeIfPresent(Bool.self, forKey: .isTop) ?? false
        isReviewed = try container.decodeIfPresent(Bool.self, forKey: .isReviewed) ?? false
        accountId = try container.decodeIfPresent(Int.self, forKey: .accountId)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        attachments = try container.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        tagRelations = try container.decodeIfPresent([TagRelation].self, forKey: .tagRelations) ?? []
    }
}
