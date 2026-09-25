import Foundation

/// The last successful notes-list payload, persisted so the list can render
/// during transient network failures. The server remains the source of truth:
/// every successful first-page refresh *replaces* this wholesale, which is
/// also how server-side deletions reconcile — a note absent from the fresh
/// payload simply is not in the next cache.
struct CachedNotesPayload: Codable, Sendable, Equatable {
    /// Bump when the on-disk shape changes; a mismatched version decodes as
    /// a cache miss rather than a crash or garbled list.
    var version: Int
    /// Origin the payload was fetched from, kept as a sanity check so a file
    /// that somehow lands under the wrong key is discarded instead of shown.
    var serverURL: URL
    /// First page of active notes, in server order.
    var notes: [Note]
    /// When the payload was fetched. Drives the "last updated" label on the
    /// offline banner.
    var savedAt: Date

    static let currentVersion = 1
}

/// Read-write storage for the offline notes cache.
///
/// Kept as a protocol so the view model can be tested against an in-memory
/// store and so previews don't touch the filesystem.
protocol NotesCacheStore: Sendable {
    /// The cached payload, or `nil` on a miss (no file, unreadable, version
    /// or server mismatch).
    func load() async -> CachedNotesPayload?
    func save(notes: [Note], savedAt: Date) async
    /// Removes the cached payload. Called on sign-out so the next account on
    /// this device cannot see the previous account's notes.
    func clear() async
}

/// File-backed cache, one JSON file per server origin.
///
/// **Isolation model.** The file name is derived from the server origin, so
/// pointing the app at a different server reads a different file — one
/// server's notes can never render under another's. Same-server account
/// changes are covered by `clear()` on sign-out (the app has no multi-account
/// support; there is exactly one signed-in identity per server at a time).
///
/// Files live in Application Support, which iOS excludes from user-visible
/// storage and includes in device encryption. This is a read cache of note
/// content, not a credential store — the token stays in the Keychain.
actor FileNotesCacheStore: NotesCacheStore {
    private let serverURL: URL
    private let fileURL: URL
    private let decoder = JSONDecoder.blinko
    private let encoder = JSONEncoder.blinko

    /// - Parameters:
    ///   - serverURL: origin of the Blinko instance this cache belongs to.
    ///   - directory: where cache files live. Defaults to
    ///     `Application Support/NotesCache`; injectable for tests.
    init(serverURL: URL, directory: URL? = nil) {
        self.serverURL = serverURL
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotesCache", isDirectory: true)
        self.fileURL = base.appendingPathComponent(
            "notes-\(Self.cacheKey(for: serverURL)).json"
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

    func load() -> CachedNotesPayload? {
        guard
            let data = try? Data(contentsOf: fileURL),
            let payload = try? decoder.decode(CachedNotesPayload.self, from: data),
            payload.version == CachedNotesPayload.currentVersion,
            payload.serverURL == serverURL
        else { return nil }
        return payload
    }

    func save(notes: [Note], savedAt: Date) {
        let payload = CachedNotesPayload(
            version: CachedNotesPayload.currentVersion,
            serverURL: serverURL,
            notes: notes,
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
actor InMemoryNotesCacheStore: NotesCacheStore {
    private let serverURL: URL
    private var payload: CachedNotesPayload?

    init(serverURL: URL = URL(string: "https://blinko.example.com")!) {
        self.serverURL = serverURL
    }

    func load() -> CachedNotesPayload? { payload }

    func save(notes: [Note], savedAt: Date) {
        payload = CachedNotesPayload(
            version: CachedNotesPayload.currentVersion,
            serverURL: serverURL,
            notes: notes,
            savedAt: savedAt
        )
    }

    func clear() { payload = nil }
}
