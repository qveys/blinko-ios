import Foundation

/// A file attached to a note, mirroring `model attachments` in Blinko's
/// `prisma/schema.prisma`.
///
/// `path` is a server-relative path (e.g. `/api/file/foo.png`), not an absolute
/// URL — resolve it against the configured host with ``url(relativeTo:)``.
struct Attachment: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    var name: String
    var path: String
    /// Bytes. Stored as a SQL `Decimal`, so the wire value may be a JSON number
    /// *or* a string; both decode here.
    var size: Int64
    /// MIME type, e.g. `image/png`. Empty when the server could not detect one.
    var type: String
    var noteId: Int?
    var accountId: Int?
    var sortOrder: Int
    let createdAt: Date
    var updatedAt: Date

    var isImage: Bool { type.hasPrefix("image/") }

    /// Resolves ``path`` against the configured server base URL.
    func url(relativeTo baseURL: URL) -> URL? {
        URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    init(
        id: Int,
        name: String,
        path: String,
        size: Int64 = 0,
        type: String = "",
        noteId: Int? = nil,
        accountId: Int? = nil,
        sortOrder: Int = 0,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.size = size
        self.type = type
        self.noteId = noteId
        self.accountId = accountId
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        size = try container.decodeFlexibleInt64(forKey: .size) ?? 0
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        noteId = try container.decodeIfPresent(Int.self, forKey: .noteId)
        accountId = try container.decodeIfPresent(Int.self, forKey: .accountId)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value the server may send as either a JSON number or a string.
    ///
    /// Prisma `Decimal` columns serialize inconsistently across drivers, and
    /// Blinko's own upsert input accepts `string | number` for attachment size.
    func decodeFlexibleInt64(forKey key: Key) throws -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int64(value)
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return string.isEmpty ? nil : Int64(Double(string) ?? 0)
        }
        return nil
    }
}
