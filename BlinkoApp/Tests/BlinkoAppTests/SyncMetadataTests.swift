import XCTest
@testable import BlinkoApp

/// `SyncMetadata` is client-side bookkeeping, not a server contract — Blinko
/// has no delta endpoint or cursor. These tests pin the inferences we make from
/// the only signal we get: page size. See docs/API-CONTRACTS.md §7.
final class SyncMetadataTests: XCTestCase {

    private let referenceDate = Date(timeIntervalSince1970: 1_714_000_000)

    private func notes(count: Int, updatedAt: Date? = nil) -> [Note] {
        let stamp = updatedAt ?? referenceDate
        // Half-open range, so count == 0 yields an empty array instead of trapping.
        return (0..<max(count, 0)).map { offset in
            Note(id: offset + 1, content: "Note \(offset + 1)", createdAt: stamp, updatedAt: stamp)
        }
    }

    /// A full page means there might be more. This is an inference, not a fact:
    /// a list of exactly `size` items reports `hasMore` until the next page
    /// comes back empty.
    func testFullPageKeepsHasMore() {
        var metadata = SyncMetadata.initial
        metadata.recordLoadedPage(notes(count: metadata.size), page: 1, now: referenceDate)

        XCTAssertTrue(metadata.hasMore)
        XCTAssertEqual(metadata.page, 1)
        XCTAssertEqual(metadata.nextPage, 2)
    }

    func testShortPageClearsHasMore() {
        var metadata = SyncMetadata.initial
        metadata.recordLoadedPage(notes(count: 5), page: 1, now: referenceDate)

        XCTAssertFalse(metadata.hasMore)
    }

    func testEmptyPageClearsHasMore() {
        var metadata = SyncMetadata.initial
        metadata.recordLoadedPage([], page: 2, now: referenceDate)

        XCTAssertFalse(metadata.hasMore)
        XCTAssertEqual(metadata.page, 2)
    }

    /// Only a first-page load counts as a refresh; appending page 2 doesn't
    /// mean the head of the list is any fresher.
    func testOnlyFirstPageUpdatesLastSyncedAt() {
        var metadata = SyncMetadata.initial

        metadata.recordLoadedPage(notes(count: 30), page: 1, now: referenceDate)
        let firstSync = metadata.lastSyncedAt

        let later = referenceDate.addingTimeInterval(600)
        metadata.recordLoadedPage(notes(count: 30), page: 2, now: later)

        XCTAssertEqual(metadata.lastSyncedAt, firstSync)
    }

    func testTracksNewestUpdatedAt() {
        var metadata = SyncMetadata.initial
        let older = referenceDate
        let newer = referenceDate.addingTimeInterval(3_600)

        metadata.recordLoadedPage(notes(count: 3, updatedAt: newer), page: 1, now: referenceDate)
        XCTAssertEqual(metadata.latestUpdatedAt, newer)

        // An older page must not drag the high-water mark backwards.
        metadata.recordLoadedPage(notes(count: 3, updatedAt: older), page: 2, now: referenceDate)
        XCTAssertEqual(metadata.latestUpdatedAt, newer)
    }

    /// Reset must restore `hasMore`, or a refresh after exhausting the list
    /// would never paginate again.
    func testResetRestoresPaging() {
        var metadata = SyncMetadata.initial
        metadata.recordLoadedPage(notes(count: 2), page: 3, now: referenceDate)
        XCTAssertFalse(metadata.hasMore)

        metadata.reset()

        XCTAssertTrue(metadata.hasMore)
        XCTAssertEqual(metadata.nextPage, 1)
    }

    /// Reset is about paging only — the freshness markers survive it, so a
    /// refresh can still tell how stale the cached list was.
    func testResetKeepsFreshnessMarkers() {
        var metadata = SyncMetadata.initial
        metadata.recordLoadedPage(notes(count: 30), page: 1, now: referenceDate)

        metadata.reset()

        XCTAssertNotNil(metadata.lastSyncedAt)
        XCTAssertNotNil(metadata.latestUpdatedAt)
    }

    func testInitialStateStartsBeforeFirstPage() {
        let metadata = SyncMetadata.initial

        XCTAssertEqual(metadata.nextPage, 1)
        XCTAssertTrue(metadata.hasMore)
        XCTAssertNil(metadata.lastSyncedAt)
        XCTAssertEqual(metadata.size, SyncMetadata.defaultPageSize)
    }
}

/// The mock services back both previews and tests, so their behaviour needs to
/// stay honest about what the real API does.
final class MockNoteServiceTests: XCTestCase {

    func testPaginatesLikeTheServer() async throws {
        let seeded = (1...45).map { index in
            Note(
                id: index,
                content: "Note \(index)",
                createdAt: Date(timeIntervalSince1970: 1_714_000_000),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(1_714_000_000 - index))
            )
        }
        let service = MockNoteService(notes: seeded)

        let first = try await service.fetchNotes(NoteListRequest(page: 1, size: 30))
        let second = try await service.fetchNotes(NoteListRequest(page: 2, size: 30))
        let third = try await service.fetchNotes(NoteListRequest(page: 3, size: 30))

        XCTAssertEqual(first.count, 30)
        XCTAssertEqual(second.count, 15)
        XCTAssertTrue(third.isEmpty)
        // Pages must not overlap.
        XCTAssertTrue(Set(first.map(\.id)).isDisjoint(with: Set(second.map(\.id))))
    }

    /// Trash is a soft delete: the note stays, flagged, and drops out of the
    /// default list because that list filters `isRecycle: false`.
    func testTrashHidesFromDefaultListButKeepsTheNote() async throws {
        let service = MockNoteService()
        let before = try await service.fetchNotes(NoteListRequest())
        let target = try XCTUnwrap(before.first)

        try await service.trash(ids: [target.id])

        let after = try await service.fetchNotes(NoteListRequest())
        XCTAssertFalse(after.contains { $0.id == target.id })

        let binned = try await service.fetchNotes(.recycleBin())
        XCTAssertTrue(binned.contains { $0.id == target.id })
    }

    func testRestoreReturnsNoteToTheDefaultList() async throws {
        let service = MockNoteService()
        let listed = try await service.fetchNotes(NoteListRequest())
        let target = try XCTUnwrap(listed.first)

        try await service.trash(ids: [target.id])
        try await service.restore(ids: [target.id])

        let after = try await service.fetchNotes(NoteListRequest())
        XCTAssertTrue(after.contains { $0.id == target.id })
    }

    /// Unlike trash, delete is permanent — the row is gone from every list.
    func testDeleteRemovesPermanently() async throws {
        let service = MockNoteService()
        let listed = try await service.fetchNotes(NoteListRequest())
        let target = try XCTUnwrap(listed.first)

        try await service.delete(ids: [target.id])

        let binned = try await service.fetchNotes(.recycleBin())
        XCTAssertFalse(binned.contains { $0.id == target.id })
        await XCTAssertThrowsErrorAsync(try await service.fetchNote(id: target.id))
    }

    func testUpsertWithoutIDCreatesAndAssignsFreshID() async throws {
        let service = MockNoteService()

        let created = try await service.createNote(content: "Brand new", type: .note)

        XCTAssertEqual(created.content, "Brand new")
        XCTAssertEqual(created.type, .note)
        let fetched = try await service.fetchNote(id: created.id)
        XCTAssertEqual(fetched.id, created.id)
    }

    /// Omitted fields mean "leave unchanged" — the behaviour `upsert` relies on.
    func testPartialUpsertLeavesOtherFieldsUntouched() async throws {
        let service = MockNoteService()
        // Note 1 is unpinned in the fixtures, so the flag genuinely changes.
        let target = try await service.fetchNote(id: 1)
        XCTAssertFalse(target.isTop)

        let updated = try await service.setTop(id: target.id, isTop: true)

        XCTAssertTrue(updated.isTop)
        XCTAssertEqual(updated.content, target.content, "content should survive a flag-only update")
        XCTAssertEqual(updated.type, target.type)
        XCTAssertEqual(updated.tags.map(\.name), target.tags.map(\.name))
    }

    /// Pinned notes sort ahead of unpinned ones regardless of recency.
    /// Seeded explicitly: the fixture list already contains a pinned note, and
    /// pinning a second one would make "first" depend on their timestamps.
    func testPinnedNotesSortFirst() async throws {
        let base = Date(timeIntervalSince1970: 1_714_000_000)
        let service = MockNoteService(notes: [
            Note(id: 1, content: "Newest", createdAt: base, updatedAt: base),
            Note(id: 2, content: "Oldest", createdAt: base, updatedAt: base.addingTimeInterval(-3_600))
        ])

        // Pin the older note; it should outrank the newer one.
        _ = try await service.setTop(id: 2, isTop: true)

        let listed = try await service.fetchNotes(NoteListRequest())
        XCTAssertEqual(listed.map(\.id), [2, 1])
    }

    func testSearchFiltersByContent() async throws {
        let service = MockNoteService()

        let results = try await service.fetchNotes(NoteListRequest(searchText: "offsite"))

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { $0.content.localizedCaseInsensitiveContains("offsite") })
    }

    func testFetchingUnknownNoteThrowsNotFound() async {
        let service = MockNoteService()
        await XCTAssertThrowsErrorAsync(try await service.fetchNote(id: 999_999))
    }
}

// MARK: - Helpers

/// `XCTAssertThrowsError` predates async, so this wraps the await.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: String = "expected an error",
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail(message, file: file, line: line)
    } catch {
        // expected
    }
}
