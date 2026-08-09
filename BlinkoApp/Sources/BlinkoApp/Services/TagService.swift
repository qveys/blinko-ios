import Foundation

protocol TagServiceProtocol: Sendable {
    func fetchTags() async throws -> [Tag]
    /// Renames a tag. The server rewrites the `#tag` text inside every note
    /// carrying it, which is why it needs the old name as well as the new one.
    func renameTag(id: Int, from oldName: String, to newName: String) async throws
    /// Deletes the tag but leaves its notes in place.
    func deleteTag(id: Int) async throws
}

/// Talks to Blinko's `/api/v1/tags/*` endpoints.
///
/// There is no "create tag" endpoint: tags are created implicitly by the server
/// when a note's content contains `#hashtags`. The client should never try to
/// create one directly.
final class TagService: TagServiceProtocol {
    private let httpClient: any HTTPClient

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func fetchTags() async throws -> [Tag] {
        // Generated tRPC query routes are POST even for reads.
        try await httpClient.perform(
            APIRequest(path: BlinkoAPI.Tags.list, method: .post)
        )
    }

    func renameTag(id: Int, from oldName: String, to newName: String) async throws {
        try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Tags.updateName,
                method: .post,
                body: TagRenameRequest(id: id, oldName: oldName, newName: newName)
            )
        )
    }

    func deleteTag(id: Int) async throws {
        // `delete-only-tag` keeps the notes; `delete-tag-with-notes` would
        // delete them too, which no UI affordance should map onto silently.
        try await httpClient.perform(
            APIRequest(
                path: BlinkoAPI.Tags.deleteOnlyTag,
                method: .post,
                body: TagIdRequest(id: id)
            )
        )
    }
}

struct TagRenameRequest: Encodable, Sendable {
    var id: Int
    var oldName: String
    var newName: String
}

struct TagIdRequest: Encodable, Sendable {
    var id: Int
}

extension Array where Element == Tag {
    /// Groups tags into `(root, children)` pairs for sidebar-style display.
    ///
    /// Tags whose parent is missing from the list are treated as roots so they
    /// never disappear from the UI.
    func groupedByParent() -> [(parent: Tag, children: [Tag])] {
        let byId = Dictionary(uniqueKeysWithValues: map { ($0.id, $0) })
        let roots = filter { $0.isRoot || byId[$0.parent] == nil }
        return roots.map { root in
            (parent: root, children: filter { $0.parent == root.id })
        }
    }
}
