import XCTest
@testable import BlinkoApp

// MARK: - HomeViewModel filter application

@MainActor
final class HomeViewModelTagFilterTests: XCTestCase {
    func testApplyTagFilterReloadsWithOnlyMatchingNotes() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let unfilteredCount = viewModel.notes.count

        // Fixture note 1 carries tags 3 (work) and 7 (work/projects).
        await viewModel.applyTagFilter(ActiveTagFilter(id: 3, fullPath: "work"))

        XCTAssertEqual(viewModel.activeTagFilter?.id, 3)
        XCTAssertFalse(viewModel.notes.isEmpty)
        XCTAssertLessThan(viewModel.notes.count, unfilteredCount)
        XCTAssertTrue(viewModel.notes.allSatisfy { note in
            note.tags.contains { $0.id == 3 }
        })
    }

    func testClearTagFilterRestoresAllNotes() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.loadNotes()
        let unfilteredCount = viewModel.notes.count

        await viewModel.applyTagFilter(ActiveTagFilter(id: 3, fullPath: "work"))
        await viewModel.clearTagFilter()

        XCTAssertNil(viewModel.activeTagFilter)
        XCTAssertEqual(viewModel.notes.count, unfilteredCount)
    }

    func testApplyingSameFilterTwiceIsANoOp() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        await viewModel.applyTagFilter(ActiveTagFilter(id: 3, fullPath: "work"))
        let notesAfterFirstApply = viewModel.notes

        await viewModel.applyTagFilter(ActiveTagFilter(id: 3, fullPath: "work"))

        XCTAssertEqual(viewModel.notes, notesAfterFirstApply)
    }

    func testClearWithoutActiveFilterDoesNotReload() async {
        let viewModel = HomeViewModel(
            noteService: MockNoteService.failing(APIError.transport("offline"))
        )

        // Would surface an error if it hit the (failing) service.
        await viewModel.clearTagFilter()

        XCTAssertFalse(viewModel.showError)
        XCTAssertTrue(viewModel.notes.isEmpty)
    }

    func testFilterWithNoMatchesYieldsEmptyList() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())

        await viewModel.applyTagFilter(ActiveTagFilter(id: 999, fullPath: "ghost"))

        XCTAssertTrue(viewModel.notes.isEmpty)
        XCTAssertNotNil(viewModel.activeTagFilter)
        XCTAssertFalse(viewModel.showError)
    }

    func testApplyTagFilterFromTagResolvesFullPath() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        // Joined tags of fixture note 1: work (3) and its child projects (7).
        let tags = APIFixtures.sampleTags
        let projects = tags.first { $0.id == 7 }!

        await viewModel.applyTagFilter(projects, in: tags)

        XCTAssertEqual(viewModel.activeTagFilter?.id, 7)
        XCTAssertEqual(viewModel.activeTagFilter?.fullPath, "work/projects")
    }

    func testApplyTagFilterDismissesSheet() async {
        let viewModel = HomeViewModel(noteService: MockNoteService())
        viewModel.isTagFilterSheetPresented = true

        await viewModel.applyTagFilter(ActiveTagFilter(id: 3, fullPath: "work"))

        XCTAssertFalse(viewModel.isTagFilterSheetPresented)
    }

    func testPaginationCarriesTagFilter() async {
        // Two pages of notes carrying the same tag: loadMore must stay
        // filtered rather than falling back to the unfiltered list.
        let tag = APIFixtures.sampleTags.first { $0.id == 3 }!
        // More than one default page (30) so loadMore has a second page.
        let notes = (1...45).map { id in
            Note(
                id: id,
                content: "note \(id) #work",
                createdAt: Date(timeIntervalSince1970: TimeInterval(id)),
                updatedAt: Date(timeIntervalSince1970: TimeInterval(id)),
                tagRelations: [TagRelation(noteId: id, tagId: tag.id, tag: tag)]
            )
        }
        let viewModel = HomeViewModel(noteService: MockNoteService(notes: notes))

        await viewModel.applyTagFilter(ActiveTagFilter(id: 3, fullPath: "work"))
        let firstPageCount = viewModel.notes.count
        await viewModel.loadMoreNotes()

        XCTAssertGreaterThan(viewModel.notes.count, firstPageCount)
        XCTAssertTrue(viewModel.notes.allSatisfy { note in
            note.tags.contains { $0.id == 3 }
        })
    }
}

// MARK: - TagFilterViewModel

@MainActor
final class TagFilterViewModelTests: XCTestCase {
    func testLoadTagsBuildsTree() async {
        let viewModel = TagFilterViewModel(tagService: MockTagService())

        await viewModel.loadTags()

        XCTAssertEqual(viewModel.tree.map(\.tag.name), ["work", "personal"])
        XCTAssertFalse(viewModel.loadFailed)
        XCTAssertFalse(viewModel.isEmpty)
    }

    func testLoadFailureSetsErrorState() async {
        let viewModel = TagFilterViewModel(
            tagService: MockTagService(error: APIError.transport("offline"))
        )

        await viewModel.loadTags()

        XCTAssertTrue(viewModel.loadFailed)
        XCTAssertTrue(viewModel.tree.isEmpty)
        XCTAssertFalse(viewModel.errorMessage.isEmpty)
    }

    func testEmptyTagListIsEmptyState() async {
        let viewModel = TagFilterViewModel(tagService: MockTagService(tags: []))

        await viewModel.loadTags()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertFalse(viewModel.loadFailed)
    }

    func testVisibleRowsRespectExpansion() async {
        let viewModel = TagFilterViewModel(tagService: MockTagService())
        await viewModel.loadTags()

        // Collapsed: only roots.
        XCTAssertEqual(viewModel.visibleRows.map(\.node.tag.name), ["work", "personal"])

        let work = viewModel.tree[0]
        viewModel.toggleExpanded(work)
        XCTAssertEqual(
            viewModel.visibleRows.map(\.node.tag.name),
            ["work", "projects", "personal"]
        )
        XCTAssertEqual(viewModel.visibleRows.map(\.depth), [0, 1, 0])

        viewModel.toggleExpanded(work)
        XCTAssertEqual(viewModel.visibleRows.map(\.node.tag.name), ["work", "personal"])
    }

    func testRetryableFailureFallsBackToCache() async {
        let cache = InMemoryTagsCacheStore()
        await cache.save(tags: APIFixtures.sampleTags, savedAt: Date())
        let viewModel = TagFilterViewModel(
            tagService: MockTagService(error: APIError.transport("offline")),
            cacheStore: cache
        )

        await viewModel.loadTags()

        XCTAssertFalse(viewModel.loadFailed)
        XCTAssertEqual(viewModel.tree.map(\.tag.name), ["work", "personal"])
    }

    func testNonRetryableFailureDoesNotReadCache() async {
        let cache = InMemoryTagsCacheStore()
        await cache.save(tags: APIFixtures.sampleTags, savedAt: Date())
        let viewModel = TagFilterViewModel(
            tagService: MockTagService(error: APIError.unauthorized(message: nil)),
            cacheStore: cache
        )

        await viewModel.loadTags()

        XCTAssertTrue(viewModel.loadFailed)
        XCTAssertTrue(viewModel.tree.isEmpty)
    }

    func testSuccessfulLoadReplacesCache() async {
        let cache = InMemoryTagsCacheStore()
        let viewModel = TagFilterViewModel(tagService: MockTagService(), cacheStore: cache)

        await viewModel.loadTags()

        let cached = await cache.load()
        XCTAssertEqual(cached?.tags.count, APIFixtures.sampleTags.count)
    }
}
