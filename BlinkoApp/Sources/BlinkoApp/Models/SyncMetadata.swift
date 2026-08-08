import Foundation

/// Client-side bookkeeping for a paged list of notes.
///
/// **This is not a server contract.** Blinko exposes no delta/changes endpoint
/// and no ETag or cursor — `/v1/note/list` is offset-paginated by `page`/`size`
/// and returns whole rows. So "sync" here means: what page are we on, did the
/// last page come back short (meaning we've reached the end), and when did we
/// last successfully refresh. Anything stronger would have to be built on
/// `updatedAt` polling. See docs/API-CONTRACTS.md § Sync.
struct SyncMetadata: Codable, Sendable, Equatable {
    /// Page number of the most recently loaded page. Blinko pages are 1-based.
    var page: Int
    /// Page size requested. The server default is 30.
    var size: Int
    /// `false` once a page returns fewer than `size` items.
    var hasMore: Bool
    /// When the first page was last successfully loaded.
    var lastSyncedAt: Date?
    /// Highest `updatedAt` seen. Useful for "what changed" heuristics and for
    /// deciding whether a cached list is stale.
    var latestUpdatedAt: Date?

    static let defaultPageSize = 30

    static let initial = SyncMetadata(
        page: 0,
        size: defaultPageSize,
        hasMore: true,
        lastSyncedAt: nil,
        latestUpdatedAt: nil
    )

    /// The page to request next.
    var nextPage: Int { page + 1 }

    /// Folds a freshly loaded page into the metadata.
    ///
    /// - Parameters:
    ///   - notes: the page just returned by the server.
    ///   - page: the page number that was requested.
    ///   - now: injected for testability.
    mutating func recordLoadedPage(_ notes: [Note], page loadedPage: Int, now: Date = Date()) {
        page = loadedPage
        hasMore = notes.count >= size
        if loadedPage <= 1 {
            lastSyncedAt = now
        }
        if let newest = notes.map(\.updatedAt).max() {
            latestUpdatedAt = max(latestUpdatedAt ?? newest, newest)
        }
    }

    /// Resets paging so the next load starts from the first page.
    mutating func reset() {
        page = 0
        hasMore = true
    }
}
