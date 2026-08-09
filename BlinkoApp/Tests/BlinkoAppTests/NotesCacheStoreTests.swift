import XCTest
@testable import BlinkoApp

/// Tests for the BLI-33 offline read cache: file persistence, per-server
/// isolation, wholesale replacement, and the version/server sanity checks
/// that turn a corrupt or mismatched file into a cache miss.
final class NotesCacheStoreTests: XCTestCase {
    private var directory: URL!
    private let serverA = URL(string: "https://blinko-a.example.com")!
    private let serverB = URL(string: "https://blinko-b.example.com")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesCacheStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func store(for server: URL) -> FileNotesCacheStore {
        FileNotesCacheStore(serverURL: server, directory: directory)
    }

    private func note(id: Int, content: String = "cached") -> Note {
        Note(id: id, content: content, createdAt: Date(), updatedAt: Date())
    }

    // MARK: - Persistence

    func testSaveThenLoadRoundTrips() async {
        let store = store(for: serverA)
        let saved = [note(id: 1), note(id: 2)]
        let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

        await store.save(notes: saved, savedAt: savedAt)
        let payload = await store.load()

        XCTAssertEqual(payload?.notes, saved)
        XCTAssertEqual(payload?.savedAt, savedAt)
        XCTAssertEqual(payload?.serverURL, serverA)
    }

    /// Persistence means surviving the store instance, not just the call: a
    /// *new* store over the same directory must read what the old one wrote —
    /// this is the cold-launch path.
    func testPayloadSurvivesStoreRecreation() async {
        await store(for: serverA).save(notes: [note(id: 7)], savedAt: Date())

        let reloaded = await store(for: serverA).load()

        XCTAssertEqual(reloaded?.notes.map(\.id), [7])
    }

    func testLoadReturnsNilWhenNothingSaved() async {
        let payload = await store(for: serverA).load()
        XCTAssertNil(payload)
    }

    func testLoadReturnsNilForCorruptFile() async throws {
        let store = store(for: serverA)
        await store.save(notes: [note(id: 1)], savedAt: Date())
        // Overwrite the payload with garbage in place.
        let file = try XCTUnwrap(
            FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?
                .compactMap { $0 as? URL }
                .first { $0.pathExtension == "json" }
        )
        try Data("not json".utf8).write(to: file)

        let payload = await store.load()

        XCTAssertNil(payload)
    }

    // MARK: - Replacement (server deletions reconcile)

    func testSaveReplacesPreviousPayloadWholesale() async {
        let store = store(for: serverA)
        await store.save(notes: [note(id: 1), note(id: 2), note(id: 3)], savedAt: Date())

        // Note 2 was deleted server-side; the fresh payload omits it.
        await store.save(notes: [note(id: 1), note(id: 3)], savedAt: Date())
        let payload = await store.load()

        XCTAssertEqual(payload?.notes.map(\.id), [1, 3])
    }

    // MARK: - Isolation

    func testServersDoNotShareCaches() async {
        await store(for: serverA).save(notes: [note(id: 1, content: "A's note")], savedAt: Date())
        await store(for: serverB).save(notes: [note(id: 2, content: "B's note")], savedAt: Date())

        let fromA = await store(for: serverA).load()
        let fromB = await store(for: serverB).load()

        XCTAssertEqual(fromA?.notes.map(\.content), ["A's note"])
        XCTAssertEqual(fromB?.notes.map(\.content), ["B's note"])
    }

    func testClearRemovesOnlyThatServersCache() async {
        await store(for: serverA).save(notes: [note(id: 1)], savedAt: Date())
        await store(for: serverB).save(notes: [note(id: 2)], savedAt: Date())

        await store(for: serverA).clear()

        let fromA = await store(for: serverA).load()
        let fromB = await store(for: serverB).load()
        XCTAssertNil(fromA)
        XCTAssertNotNil(fromB)
    }

    /// Distinct origins must map to distinct files even when they differ only
    /// in port or scheme — the docs promise no lossy sanitization.
    func testCacheKeyDistinguishesSimilarOrigins() {
        let urls = [
            "https://blinko.example.com",
            "https://blinko.example.com:8443",
            "http://blinko.example.com",
            "https://blinko.example.co",
        ].map { URL(string: $0)! }

        let keys = urls.map(FileNotesCacheStore.cacheKey(for:))

        XCTAssertEqual(Set(keys).count, urls.count)
        // Keys must also be filesystem-safe.
        for key in keys {
            XCTAssertNil(key.rangeOfCharacter(from: CharacterSet(charactersIn: "/+=")))
        }
    }

    /// A payload written for one server must not load from a store pointed at
    /// another, even if the file lands under the wrong key somehow.
    func testMismatchedServerInPayloadIsACacheMiss() async throws {
        await store(for: serverA).save(notes: [note(id: 1)], savedAt: Date())
        // Simulate the wrong-file scenario by copying A's file to B's path.
        let keyA = FileNotesCacheStore.cacheKey(for: serverA)
        let keyB = FileNotesCacheStore.cacheKey(for: serverB)
        let fileA = directory.appendingPathComponent("notes-\(keyA).json")
        let fileB = directory.appendingPathComponent("notes-\(keyB).json")
        try FileManager.default.copyItem(at: fileA, to: fileB)

        let fromB = await store(for: serverB).load()

        XCTAssertNil(fromB)
    }
}
