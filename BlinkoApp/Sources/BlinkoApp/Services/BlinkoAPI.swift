import Foundation

/// Paths for the Blinko REST API, relative to the `/api` base URL.
///
/// The `/api/v1/*` routes are generated from Blinko's tRPC routers by
/// `trpc-to-openapi`; `/api/file/*` are hand-written Express routes. A running
/// instance serves the authoritative merged spec at `/api/openapi.json`.
///
/// Only endpoints the client actually uses live here. See
/// docs/API-CONTRACTS.md for the full inventory and the known gaps.
enum BlinkoAPI {
    /// Default port for a self-hosted Blinko instance.
    static let defaultPort = 1111

    /// The API root for a given server origin, e.g. `https://blinko.example.com`.
    static func baseURL(forServer server: URL) -> URL {
        server.appendingPathComponent("api")
    }

    enum Auth {
        static let login = "v1/user/login"
        static let canRegister = "v1/user/can-register"
        static let regenerateToken = "v1/user/regen-token"
        static let userDetail = "v1/user/detail"
        static let upsertUser = "v1/user/upsert"
    }

    enum Notes {
        static let list = "v1/note/list"
        static let detail = "v1/note/detail"
        static let upsert = "v1/note/upsert"
        static let batchTrash = "v1/note/batch-trash"
        static let batchDelete = "v1/note/batch-delete"
        static let batchUpdate = "v1/note/batch-update"
        static let clearRecycleBin = "v1/note/clear-recycle-bin"
        static let dailyReviewList = "v1/note/daily-review-list"
        static let review = "v1/note/review"
        static let share = "v1/note/share"
        static let listByIds = "v1/note/list-by-ids"
        static let relatedNotes = "v1/note/related-notes"
        static let history = "v1/note/history"
    }

    enum Tags {
        static let list = "v1/tags/list"
        static let updateName = "v1/tags/update-name"
        static let updateIcon = "v1/tags/update-icon"
        static let batchUpdate = "v1/tags/batch-update"
        /// Removes the tag but keeps the notes.
        static let deleteOnlyTag = "v1/tags/delete-only-tag"
        /// Removes the tag *and* every note carrying it. Destructive.
        static let deleteTagWithNotes = "v1/tags/delete-tag-with-notes"
    }

    enum Files {
        static let upload = "file/upload"
        static let delete = "file/delete"

        /// Download path for an attachment's stored `path`.
        static func download(path: String) -> String {
            path.hasPrefix("/") ? String(path.dropFirst()) : path
        }
    }

    /// Unauthenticated endpoints — useful for a "test connection" screen.
    enum Public {
        static let serverVersion = "v1/public/server-version"
        static let siteInfo = "v1/public/site-info"
        static let oauthProviders = "v1/public/oauth-providers"
    }
}
