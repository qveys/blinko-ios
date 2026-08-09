import XCTest
@testable import BlinkoApp

/// Tests for the pure display helpers on `Note` (title/snippet extraction,
/// heading stripping, inline hashtags). These mirror Blinko web's
/// "first line is the title, rest is the snippet" presentation.
final class NoteDisplayTests: XCTestCase {

    private func note(_ content: String, type: NoteType = .note) -> Note {
        Note(id: 1, content: content, type: type, createdAt: Date(), updatedAt: Date())
    }

    // MARK: - Title

    func testTitleIsFirstNonEmptyLine() {
        XCTAssertEqual(note("Quarter plan\nDetails follow.").displayTitle, "Quarter plan")
    }

    func testTitleSkipsLeadingBlankLines() {
        XCTAssertEqual(note("\n\nReal title\nbody").displayTitle, "Real title")
    }

    func testTitleStripsATXHeadingMarkers() {
        XCTAssertEqual(note("# Heading\nbody").displayTitle, "Heading")
        XCTAssertEqual(note("## Subheading\nbody").displayTitle, "Subheading")
        XCTAssertEqual(note("###### Deepest\nbody").displayTitle, "Deepest")
    }

    func testTitleDoesNotStripHashesMidLine() {
        // Only leading `#` runs are heading markers; a body hashtag stays.
        XCTAssertEqual(note("Note with #work tag\nbody").displayTitle, "Note with #work tag")
    }

    func testTitleFromSingleLine() {
        XCTAssertEqual(note("Only a title").displayTitle, "Only a title")
    }

    func testTitleEmptyWhenContentEmpty() {
        XCTAssertEqual(note("").displayTitle, "")
    }

    func testTitleEmptyWhenContentWhitespaceOnly() {
        XCTAssertEqual(note("   \n\t\n ").displayTitle, "")
    }

    // MARK: - Snippet

    func testSnippetIsEverythingAfterFirstLine() {
        XCTAssertEqual(note("Title\nFirst.\nSecond.").displaySnippet, "First.\nSecond.")
    }

    func testSnippetTrimsSurroundingWhitespace() {
        XCTAssertEqual(note("Title\n\n\nBody\n").displaySnippet, "Body")
    }

    func testSnippetEmptyWhenSingleLine() {
        XCTAssertEqual(note("Only a title").displaySnippet, "")
    }

    func testSnippetEmptyWhenContentEmpty() {
        XCTAssertEqual(note("").displaySnippet, "")
    }

    func testSnippetDoesNotStripHeadingMarkersFromBody() {
        // The second line keeps its markdown; only the title line is normalised.
        XCTAssertEqual(note("Title\n## Sub\nMore").displaySnippet, "## Sub\nMore")
    }

    // MARK: - isEmpty

    func testIsEmptyTrueForBlankContent() {
        XCTAssertTrue(note("").isEmpty)
        XCTAssertTrue(note("   ").isEmpty)
        XCTAssertTrue(note("\n\n\t").isEmpty)
    }

    func testIsEmptyFalseForContent() {
        XCTAssertFalse(note("x").isEmpty)
        XCTAssertFalse(note("\nbody").isEmpty)
    }

    // MARK: - Presentation flags

    func testIsPinnedMirrorsIsTop() {
        XCTAssertTrue(note("x", type: .note).isTop == false)
        let pinned = Note(id: 1, content: "x", isTop: true, createdAt: Date(), updatedAt: Date())
        XCTAssertTrue(pinned.isPinned)
    }

    func testIsTodoOnlyForTodoType() {
        XCTAssertFalse(note("x", type: .note).isTodo)
        XCTAssertTrue(note("x", type: .todo).isTodo)
        XCTAssertFalse(note("x", type: .blinko).isTodo)
    }

    func testHasAttachmentsReflectsCount() {
        XCTAssertFalse(note("x").hasAttachments)
        let base = Date()
        let with = Note(
            id: 1, content: "x",
            attachments: [Attachment(id: 1, name: "a", path: "/p", size: 1, type: "image/png", createdAt: base, updatedAt: base)],
            createdAt: base, updatedAt: base
        )
        XCTAssertTrue(with.hasAttachments)
    }

    // MARK: - Inline hashtags

    func testInlineHashtagsExtractedInOrderUnique() {
        let tags = note("Hello #work and #work again, then #home/projects")
        // "work" appears twice but is deduped; trailing punctuation is trimmed.
        XCTAssertEqual(tags.inlineHashtags, ["work", "home/projects"])
    }

    func testInlineHashtagsIgnoresLoneHash() {
        let tags = note("# heading not a tag\nand # real one")
        // "# " (heading) and "#" alone are not tags; only "#real" would count.
        XCTAssertEqual(tags.inlineHashtags, [])
    }

    func testInlineHashtagsTrimsTrailingPunctuation() {
        let tags = note("See #work, then #home.")
        XCTAssertEqual(tags.inlineHashtags, ["work", "home"])
    }

    func testInlineHashtagsEmptyWhenNone() {
        XCTAssertEqual(note("plain text no tags").inlineHashtags, [])
    }
}
