import Foundation

/// The last successful `/tags/list` payload, persisted so the tag filter
/// sheet can open during transient network failures. The server remains the
/// source of truth: every successful fetch *replaces* this wholesale, which
/// is also how server-side tag deletions reconcile.
///
/// Mirrors BLI-33's notes read cache (`CachedNotesPayload`), kept separate
/// because the two lists refresh on different cadences and the notes cache
/// lives on its own branch.
struct CachedTagsPayload: Codable, Sendable, Equatable {
    /// Bump when the on-disk shape changes; a mismatched version decodes as
    /// a cache miss rather than a crash or garbled tree.
    var version: Int
    /// Origin the payload was fetched from, kept as a sanity check so a file
    /// that somehow lands under the wrong key is discarded instead of shown.
    var serverURL: URL
    /// Flat tag rows in server order; the tree is rebuilt on read.
    var tags: [Tag]
    /// When the payload was fetched.
    var savedAt: Date

    static let currentVersion = 1
}

/// Read-write storage for the offline tags cache.
///
/// Kept as a protocol so view models can be tested against an in-memory
/// store and so previews don't touch the filesystem.
protocol TagsCacheStore: Sendable {
    /// The cached payload, or `nil` on a miss (no file, unreadable, version
    /// or server mismatch).
    func load() async -> CachedTagsPayload?
    func save(tags: [Tag], savedAt: Date) async
    /// Removes the cached payload. Called on sign-out so the next account on
    /// this device cannot see the previous account's tags.
    func clear() async
}

/// File-backed cache, one JSON file per server origin.
///
/// **Isolation model.** The file name is derived from the server origin, so
/// pointing the app at a different server reads a different file — one
/// server's tags can never render under another's. Same-server account
/// changes are covered by `clear()` on sign-out.
///
/// Files live in Application Support, which iOS excludes from user-visible
/// storage and includes in device encryption.
actor FileTagsCacheStore: TagsCacheStore {
    private let serverURL: URL
    private let fileURL: URL
    private let decoder = JSONDecoder.blinko
    private let encoder = JSONEncoder.blinko

    /// - Parameters:
    ///   - serverURL: origin of the Blinko instance this cache belongs to.
    ///   - directory: where cache files live. Defaults to
    ///     `Application Support/TagsCache`; injectable for tests.
    init(serverURL: URL, directory: URL? = nil) {
        self.serverURL = serverURL
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TagsCache", isDirectory: true)
        self.fileURL = base.appendingPathComponent(
            "tags-\(Self.cacheKey(for: serverURL)).json"
        )
    }

    /// Stable, filesystem-safe key for a server origin. Base64url keeps the
    /// full origin (scheme + host + port) in the name, so two servers can
    /// never collide the way a lossy sanitization could.
    static func cacheKey(for serverURL: URL) -> String {
        Data(serverURL.absoluteString.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    func load() -> CachedTagsPayload? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let payload = try? decoder.decode(CachedTagsPayload.self, from: data),
            payload.version == CachedTagsPayload.currentVersion,
            payload.serverURL == serverURL
        else { return nil }
        return payload
    }

    func save(tags: [Tag], savedAt: Date) {
        let payload = CachedTagsPayload(
            version: CachedTagsPayload.currentVersion,
            serverURL: serverURL,
            tags: tags,
            savedAt: savedAt
        )
        guard let data = try? encoder.encode(payload) else { return }
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        // Atomic so a crash mid-write leaves the previous payload intact
        // rather than a truncated file.
        try? data.write(to: fileURL, options: .atomic)
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// In-memory store for tests and previews.
actor InMemoryTagsCacheStore: TagsCacheStore {
    private let serverURL: URL
    private var payload: CachedTagsPayload?

    init(serverURL: URL = URL(string: "https://blinko.example.com")!) {
        self.serverURL = serverURL
    }

    func load() -> CachedTagsPayload? { payload }

    func save(tags: [Tag], savedAt: Date) {
        payload = CachedTagsPayload(
            version: CachedTagsPayload.currentVersion,
            serverURL: serverURL,
            tags: tags,
            savedAt: savedAt
        )
    }

    func clear() { payload = nil }
}
