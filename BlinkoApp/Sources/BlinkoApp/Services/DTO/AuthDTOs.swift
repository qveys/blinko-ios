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
/// does not follow the casing of the generated tRPC routes. The success body
/// spreads `FileService.uploadFileStream`'s return value, so the storage keys
/// are `filePath`/`fileName` (verified against upstream `main` and the web
/// client, which destructures `{fileName, filePath, type, size}`). `path` is
/// also accepted as a legacy fallback since our earlier docs recorded it.
struct AttachmentUploadResponse: Decodable, Sendable {
    let message: String
    let status: Int
    /// Server-relative path, e.g. `/api/file/1712345678-photo.png` (S3
    /// deployments return an absolute URL instead). Resolve for display with
    /// ``Attachment/url(relativeTo:)``.
    let path: String
    let type: String
    let size: Int64
    /// The stored (timestamped, space-collapsed) filename. Falls back to the
    /// path's last component when the server omits `fileName`, because
    /// `note/upsert` requires a name.
    let name: String

    enum CodingKeys: String, CodingKey {
        case message = "Message"
        case status, type, size
        case filePath, fileName, path
    }

    /// Memberwise construction, for mocks and previews.
    init(message: String = "Success", status: Int = 200, path: String, type: String, size: Int64, name: String) {
        self.message = message
        self.status = status
        self.path = path
        self.type = type
        self.size = size
        self.name = name
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        status = try container.decodeIfPresent(Int.self, forKey: .status) ?? 200
        guard let storedPath = try container.decodeIfPresent(String.self, forKey: .filePath)
            ?? container.decodeIfPresent(String.self, forKey: .path)
        else {
            throw DecodingError.keyNotFound(
                CodingKeys.filePath,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Upload response has neither filePath nor path."
                )
            )
        }
        path = storedPath
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
        size = try container.decodeFlexibleInt64(forKey: .size) ?? 0
        let serverName = try container.decodeIfPresent(String.self, forKey: .fileName)
        if let serverName, !serverName.isEmpty {
            name = serverName
        } else {
            name = (storedPath as NSString).lastPathComponent
        }
    }
}
