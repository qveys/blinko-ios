import Foundation

/// The signed-in account, mirroring the subset of `model accounts` that the
/// login and user-detail endpoints return.
///
/// Deliberately excludes `password` and `apiToken` — the token is handled by
/// ``AuthStore`` and never carried on the domain model.
struct User: Identifiable, Codable, Sendable, Equatable {
    let id: Int
    var name: String
    var nickname: String
    var image: String
    var role: String
    var loginType: String

    /// `nickname` when set, otherwise the login `name`.
    var displayName: String { nickname.isEmpty ? name : nickname }

    var isSuperAdmin: Bool { role == "superadmin" }

    init(
        id: Int,
        name: String,
        nickname: String = "",
        image: String = "",
        role: String = "",
        loginType: String = ""
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.image = image
        self.role = role
        self.loginType = loginType
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        nickname = try container.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        // The login response types `image` as nullable.
        image = try container.decodeIfPresent(String.self, forKey: .image) ?? ""
        role = try container.decodeIfPresent(String.self, forKey: .role) ?? ""
        loginType = try container.decodeIfPresent(String.self, forKey: .loginType) ?? ""
    }
}
