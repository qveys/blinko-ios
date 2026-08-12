import XCTest
@testable import BlinkoApp

/// Tests for the BLI-39 typeahead: token detection at the caret, path-aware
/// suggestion filtering, `#tag ` insertion, and the editor view model's
/// suggestion state machine.
final class TagTypeaheadTests: XCTestCase {

    // MARK: - Fixtures

    private static let base = Date(timeIntervalSince1970: 1_725_000_000)

    /// `#work`, `#work/projects`, `#home`, `#network` — covers nesting and
    /// the prefix-vs-substring ranking case (`wo` hits both `work` and
    /// `network`).
    private static func sampleTags() -> [Tag] {
        [
            Tag(id: 1, name: "work", createdAt: base, updatedAt: base),
            Tag(id: 2, name: "projects", parent: 1, createdAt: base, updatedAt: base),
            Tag(id: 3, name: "home", createdAt: base, updatedAt: base),
            Tag(id: 4, name: "network", createdAt: base, updatedAt: base),
        ]
    }

    private func caret(_ text: String) -> (String, Int) {
        // `|` marks the caret in test fixtures.
        let parts = text.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let before = String(parts[0])
        let after = parts.count > 1 ? String(parts[1]) : ""
        return (before + after, before.utf16.count)
    }

    // MARK: - Token detection

    func testHashAtStartOfTextIsActive() {
        let (text, offset) = caret("#wor|")
        let token = TagTypeahead.activeToken(in: text, caretUTF16Offset: offset)
        XCTAssertEqual(token, .init(query: "wor", start: 0, end: 4))
    }

    func testHashAfterSpaceIsActive() {
        let (text, offset) = caret("Plan #wo|")
        let token = TagTypeahead.activeToken(in: text, caretUTF16Offset: offset)
        XCTAssertEqual(token?.query, "wo")
        XCTAssertEqual(token?.start, 5)
    }

    func testBareHashHasEmptyQuery() {
        let (text, offset) = caret("note #|")
        XCTAssertEqual(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset)?.query, "")
    }

    func testNestedPathQueryIsPreserved() {
        let (text, offset) = caret("#work/pro|")
        XCTAssertEqual(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset)?.query, "work/pro")
    }

    func testMidWordHashDoesNotTrigger() {
        // `no#tag` — the `#` is glued to a word (URL fragments, anchors).
        let (text, offset) = caret("no#tag|")
        XCTAssertNil(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
    }

    func testSpaceTerminatesToken() {
        let (text, offset) = caret("#work |")
        XCTAssertNil(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
    }

    func testNewlineTerminatesToken() {
        let (text, offset) = caret("#work\n|")
        XCTAssertNil(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
    }

    func testCaretInsideTokenCutsQueryAtCaret() {
        // Suggestions should match what's left of the caret, not the whole word.
        let (text, offset) = caret("#wo|rk")
        XCTAssertEqual(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset)?.query, "wo")
    }

    func testCaretBeforeHashDoesNotTrigger() {
        let (text, offset) = caret("|#work")
        XCTAssertNil(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
    }

    func testPlainTextHasNoToken() {
        let (text, offset) = caret("just some text|")
        XCTAssertNil(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
    }

    func testOutOfBoundsCaretIsNil() {
        XCTAssertNil(TagTypeahead.activeToken(in: "#a", caretUTF16Offset: 99))
        XCTAssertNil(TagTypeahead.activeToken(in: "#a", caretUTF16Offset: -1))
    }

    func testEmojiBeforeTokenKeepsUTF16OffsetsHonest() {
        // 🎉 is 2 UTF-16 units; the token offsets must be UTF-16, not chars.
        let (text, offset) = caret("🎉 #wo|")
        let token = TagTypeahead.activeToken(in: text, caretUTF16Offset: offset)
        XCTAssertEqual(token?.query, "wo")
        XCTAssertEqual(token?.start, 3)
        XCTAssertEqual(token?.end, 6)
    }

    // MARK: - Suggestion filtering

    func testEmptyQueryReturnsAllTags() {
        let suggestions = TagTypeahead.suggestions(matching: "", in: Self.sampleTags())
        XCTAssertEqual(suggestions.map(\.fullPath), ["work", "work/projects", "home", "network"])
    }

    func testFilterIsCaseInsensitive() {
        let suggestions = TagTypeahead.suggestions(matching: "WORK", in: Self.sampleTags())
        XCTAssertEqual(suggestions.map(\.fullPath), ["work", "work/projects", "network"])
    }

    func testPrefixMatchesRankAboveSubstringMatches() {
        let suggestions = TagTypeahead.suggestions(matching: "wo", in: Self.sampleTags())
        // `work`/`work/projects` are prefix hits; `network` matches only as a
        // substring and must come after.
        XCTAssertEqual(suggestions.map(\.fullPath), ["work", "work/projects", "network"])
    }

    func testPathAwareFilterMatchesNestedTag() {
        // The acceptance criterion: `#work/pro` matches `#work/projects`.
        let suggestions = TagTypeahead.suggestions(matching: "work/pro", in: Self.sampleTags())
        XCTAssertEqual(suggestions.map(\.fullPath), ["work/projects"])
    }

    func testLeafQueryMatchesNestedTagBySubstring() {
        let suggestions = TagTypeahead.suggestions(matching: "proj", in: Self.sampleTags())
        XCTAssertEqual(suggestions.map(\.fullPath), ["work/projects"])
    }

    func testNoMatchReturnsEmpty() {
        XCTAssertTrue(TagTypeahead.suggestions(matching: "zzz", in: Self.sampleTags()).isEmpty)
    }

    func testMissingParentFallsBackToLeafName() {
        // Orphaned child (parent row absent from payload) still renders.
        let orphan = Tag(id: 9, name: "stray", parent: 42, createdAt: Self.base, updatedAt: Self.base)
        let suggestions = TagTypeahead.suggestions(matching: "stray", in: [orphan])
        XCTAssertEqual(suggestions.map(\.fullPath), ["stray"])
    }

    // MARK: - Insertion

    func testInsertReplacesTokenAndAppendsSpace() throws {
        let (text, offset) = caret("Plan #wor|")
        let token = try XCTUnwrap(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
        let suggestion = try XCTUnwrap(
            TagTypeahead.suggestions(matching: "wor", in: Self.sampleTags()).first
        )
        let insertion = try XCTUnwrap(TagTypeahead.insert(suggestion, replacing: token, in: text))
        XCTAssertEqual(insertion.content, "Plan #work ")
        XCTAssertEqual(insertion.caretUTF16Offset, "Plan #work ".utf16.count)
    }

    func testInsertNestedTagUsesFullPath() throws {
        let (text, offset) = caret("#pro|")
        let token = try XCTUnwrap(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
        let suggestion = try XCTUnwrap(
            TagTypeahead.suggestions(matching: "pro", in: Self.sampleTags()).first
        )
        let insertion = try XCTUnwrap(TagTypeahead.insert(suggestion, replacing: token, in: text))
        XCTAssertEqual(insertion.content, "#work/projects ")
    }

    func testInsertWithCaretMidTokenConsumesWholeToken() throws {
        // Accepting `#wo|rk` must not leave a stray `rk` behind.
        let (text, offset) = caret("see #wo|rk now")
        let token = try XCTUnwrap(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
        let suggestion = TagTypeahead.Suggestion(
            tag: Self.sampleTags()[1], fullPath: "work/projects"
        )
        let insertion = try XCTUnwrap(TagTypeahead.insert(suggestion, replacing: token, in: text))
        XCTAssertEqual(insertion.content, "see #work/projects  now")
        XCTAssertEqual(insertion.caretUTF16Offset, "see #work/projects ".utf16.count)
    }

    func testInsertPreservesSurroundingText() throws {
        let (text, offset) = caret("a #h| z")
        let token = try XCTUnwrap(TagTypeahead.activeToken(in: text, caretUTF16Offset: offset))
        let home = TagTypeahead.Suggestion(tag: Self.sampleTags()[2], fullPath: "home")
        let insertion = try XCTUnwrap(TagTypeahead.insert(home, replacing: token, in: text))
        XCTAssertEqual(insertion.content, "a #home  z")
    }

    func testInsertWithStaleTokenReturnsNil() {
        // Token computed against longer text than we now have.
        let stale = TagTypeahead.ActiveToken(query: "wo", start: 40, end: 43)
        let home = TagTypeahead.Suggestion(
            tag: Tag(id: 3, name: "home", createdAt: Self.base, updatedAt: Self.base),
            fullPath: "home"
        )
        XCTAssertNil(TagTypeahead.insert(home, replacing: stale, in: "short"))
    }
}

/// Tests for the editor view model's suggestion state: lazy tag loading,
/// no-match vs zero-tags, insertion through the view model, and dismissal.
@MainActor
final class NoteEditorViewModelTypeaheadTests: XCTestCase {

    private static let base = Date(timeIntervalSince1970: 1_725_000_000)

    private static func tags() -> [Tag] {
        [
            Tag(id: 1, name: "work", createdAt: base, updatedAt: base),
            Tag(id: 2, name: "projects", parent: 1, createdAt: base, updatedAt: base),
        ]
    }

    private func makeViewModel(tags: [Tag]? = nil, tagError: (any Error)? = nil) -> NoteEditorViewModel {
        NoteEditorViewModel(
            noteService: MockNoteService(),
            tagService: MockTagService(tags: tags ?? Self.tags(), error: tagError)
        )
    }

    /// Drives the caret and waits out the async first-fetch that `#` kicks off.
    private func type(_ text: String, into viewModel: NoteEditorViewModel) async {
        viewModel.content = text
        viewModel.caretMoved(toUTF16Offset: text.utf16.count)
        // Let the tag-fetch task land and refilter (bounded, not flaky).
        let deadline = Date().addingTimeInterval(2)
        while viewModel.isLoadingTags, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        await Task.yield()
    }

    func testHashSurfacesAllTags() async {
        let viewModel = makeViewModel()
        await type("note #", into: viewModel)
        XCTAssertEqual(viewModel.tagSuggestions.map(\.fullPath), ["work", "work/projects"])
        XCTAssertFalse(viewModel.showNoTagMatch)
    }

    func testTypedQueryFilters() async {
        let viewModel = makeViewModel()
        await type("note #pro", into: viewModel)
        XCTAssertEqual(viewModel.tagSuggestions.map(\.fullPath), ["work/projects"])
    }

    func testNoMatchShowsHintWithoutBlocking() async {
        let viewModel = makeViewModel()
        await type("note #zzz", into: viewModel)
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertTrue(viewModel.showNoTagMatch)
        // Content is untouched — free typing continues.
        XCTAssertEqual(viewModel.content, "note #zzz")
    }

    func testZeroTagAccountShowsNoPicker() async {
        let viewModel = makeViewModel(tags: [])
        await type("note #any", into: viewModel)
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertFalse(viewModel.showNoTagMatch)
    }

    func testFailedTagLoadNeverBlocksTyping() async {
        let viewModel = makeViewModel(tagError: APIError.transport("offline"))
        await type("note #wo", into: viewModel)
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertFalse(viewModel.showNoTagMatch)
        XCTAssertFalse(viewModel.isLoadingTags)
    }

    func testSpaceDismissesSuggestions() async {
        let viewModel = makeViewModel()
        await type("note #wo", into: viewModel)
        XCTAssertFalse(viewModel.tagSuggestions.isEmpty)
        await type("note #wo ", into: viewModel)
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertFalse(viewModel.showNoTagMatch)
    }

    func testAcceptSuggestionSplicesTokenAndReturnsCaret() async throws {
        let viewModel = makeViewModel()
        await type("plan #pro", into: viewModel)
        let suggestion = try XCTUnwrap(viewModel.tagSuggestions.first)
        let newCaret = viewModel.acceptSuggestion(suggestion)
        XCTAssertEqual(viewModel.content, "plan #work/projects ")
        XCTAssertEqual(newCaret, "plan #work/projects ".utf16.count)
        // Surface is gone after acceptance.
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
    }

    func testAcceptWithoutActiveTokenIsNoOp() {
        let viewModel = makeViewModel()
        viewModel.content = "text"
        let suggestion = TagTypeahead.Suggestion(
            tag: Tag(id: 1, name: "work", createdAt: Self.base, updatedAt: Self.base),
            fullPath: "work"
        )
        XCTAssertNil(viewModel.acceptSuggestion(suggestion))
        XCTAssertEqual(viewModel.content, "text")
    }

    func testNilTagServiceDisablesTypeahead() {
        let viewModel = NoteEditorViewModel(noteService: MockNoteService())
        viewModel.content = "note #wo"
        viewModel.caretMoved(toUTF16Offset: 8)
        XCTAssertTrue(viewModel.tagSuggestions.isEmpty)
        XCTAssertFalse(viewModel.isLoadingTags)
    }
}
