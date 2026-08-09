import Foundation

/// A tag, mirroring `model tag` in Blinko's `prisma/schema.prisma`.
///
/// Tags form a tree: `parent` is `0` for a root tag, otherwise the `id` of the
/// parent tag. The server stores only the leaf `name` per row — a nested tag
/// like `#work/projects` is two rows, not one row with a slash in `name`.
struct Tag: Identifiable, Codable, Sendable, Equatable, Hashable {
    let id: Int
    var name: String
    var icon: String
    /// `0` means "root tag"; otherwise the parent tag's `id`.
    var parent: Int
    var accountId: Int?
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    var isRoot: Bool { parent == 0 }

    init(
        id: Int,
        name: String,
        icon: String = "",
        parent: Int = 0,
        accountId: Int? = nil,
        sortOrder: Int = 0,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.parent = parent
        self.accountId = accountId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        parent = try container.decodeIfPresent(Int.self, forKey: .parent) ?? 0
        accountId = try container.decodeIfPresent(Int.self, forKey: .accountId)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

/// A row of the `tagsToNote` join table as embedded in a note payload.
///
/// The server returns the join row with the full `tag` nested inside, so this
/// exists to unwrap that one level. Prefer `Note.tags` over reading it directly.
struct TagRelation: Codable, Sendable, Equatable {
    let noteId: Int
    let tagId: Int
    let tag: Tag

    init(noteId: Int, tagId: Int, tag: Tag) {
        self.noteId = noteId
        self.tagId = tagId
        self.tag = tag
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tag = try container.decode(Tag.self, forKey: .tag)
        // Fall back to the nested tag's id: some payloads omit the join columns.
        noteId = try container.decodeIfPresent(Int.self, forKey: .noteId) ?? 0
        tagId = try container.decodeIfPresent(Int.self, forKey: .tagId) ?? tag.id
    }
}
