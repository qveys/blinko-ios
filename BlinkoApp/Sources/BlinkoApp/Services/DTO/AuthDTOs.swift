import Foundation

/// Request body for `POST /api/v1/user/login`.
///
/// `name` is the account's login name, not the nickname.
struct LoginRequest: Encodable, Sendable {
    var name: String
    var password: String
}

/// Response from `POST /api/v1/user/login`.
///
/// The `token` is a long-lived API token — the server also writes it to
/// `accounts.apiToken`, so it stays valid until the user regenerates it. There
/// is no refresh endpoint and no expiry in the response; treat a `401` on any
/// subsequent call as "token no longer valid, re-authenticate".
struct LoginResponse: Decodable, Sendable {
    let id: Int
    let name: String
    let nickname: String
    let role: String
    let token: String
    let image: String?
    let loginType: String

    /// The account portion of the response, without the credential.
    var user: User {
        User(
            id: id,
            name: name,
            nickname: nickname,
            image: image ?? "",
            role: role,
            loginType: loginType
        )
    }
}

/// Response from `POST /api/file/upload`.
///
/// Note the capitalized `Message` key — this route is hand-written Express and
/// does not follow the casing of the generated tRPC routes.
struct AttachmentUploadResponse: Decodable, Sendable {
    let message: String
    let status: Int
    let path: String
    let type: String
    let size: Int64
    /// Not returned by the server; filled in by ``AttachmentService`` from the
    /// filename it uploaded, because `upsert` requires a name.
    var name: String = ""

    enum CodingKeys: String, CodingKey {
        case message = "Message"
        case status, path, type, size
    }

    /// Convenience init for tests and mocks — skips JSON decoding.
    init(path: String, type: String = "", size: Int64 = 0, name: String = "", message: String = "", status: Int = 200) {
        self.path = path
        self.type = type
        self.size = size
        self.name = name.isEmpty ? (path as NSString).lastPathComponent : name
        self.message = message
        self.status = status
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 200
        path = try container.decode(String.self, forKey: .path)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        size = try container.decodeFlexibleInt64(forKey: .size) ?? 0
        name = (path as NSString).lastPathComponent
    }
}
