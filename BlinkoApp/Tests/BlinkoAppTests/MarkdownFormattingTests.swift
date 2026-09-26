import XCTest
@testable import BlinkoApp

@MainActor
final class MarkdownFormattingTests: XCTestCase {

    // MARK: - Inline: bold

    func testToggleBold() {
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        // The delimiters wrap exactly the selection: "ello" inside "hello world"
        // becomes h**ello** world, with the selection still covering "ello".
        XCTAssertEqual(result.text, "h**ello** world")
        XCTAssertEqual(result.selectedOffsets().lowerBound, 3)
        XCTAssertEqual(result.selectedOffsets().upperBound, 7)
    }

    func testToggleBoldTwice() {
        // Toggle back off: **bold** -> bold
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)
        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "bold")
    }

    func testToggleBoldEmptySelection() {
        // Empty selection still inserts delimiters
        let text = "hello"
        let selection: Range<String.Index> = text.startIndex..<text.endIndex

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "**hello**")
        // Selection should be between the delimiters
        XCTAssertEqual(result.selectedOffsets().lowerBound, 2)
        XCTAssertEqual(result.selectedOffsets().upperBound, 6)
    }

    func testToggleBoldAtEnd() {
        // Selection at the end
        let text = "world"
        let selection = text.index(text.startIndex, offsetBy: 5)..<text.endIndex
        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        // An empty selection inserts both delimiters with the caret between
        // them, so typing immediately produces bold text. (The previous
        // expectation asked for offsets 5...10 in a 7-character result.)
        XCTAssertEqual(result.text, "world****")
        XCTAssertEqual(result.selectedOffsets().lowerBound, 7)
        XCTAssertEqual(result.selectedOffsets().upperBound, 7)
    }

    // MARK: - Inline: italic

    func testToggleItalic() {
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleInline(.italic, in: text, selection: selection)
        // Same rule as bold: the delimiters wrap the selection itself.
        XCTAssertEqual(result.text, "h*ello* world")
    }

    // MARK: - Inline: code

    func testToggleCode() {
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleInline(.code, in: text, selection: selection)
        XCTAssertEqual(result.text, "h`ello` world")
    }

    // MARK: - Inline: toggle off

    func testToggleInlineUnwraps() {
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "bold")
    }

    // MARK: - Inline: mixed case

    func testToggleBoldOnAlreadyFormatted() {
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "bold")
    }

    // MARK: - Heading

    func testToggleHeadingLevel1() {
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleHeading(level: 1, in: text, selection: selection)
        XCTAssertEqual(result.text, "# hello world")
    }

    func testToggleHeadingLevel1ThenLevel2() {
        let text = "# heading"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 10)

        let result = MarkdownFormatting.toggleHeading(level: 2, in: text, selection: selection)
        XCTAssertEqual(result.text, "## heading")
    }

    func testToggleHeadingAlreadyLevel1() {
        // Applying level 1 to an already-level-1 heading re-strips to level 1 (idempotent)
        let text = "# heading"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 10)

        let result = MarkdownFormatting.toggleHeading(level: 1, in: text, selection: selection)
        XCTAssertEqual(result.text, "# heading")
    }

    // MARK: - Private helpers: headingLevel(of:)

    func testHeadingLevelOfValidHeading() {
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "# heading"), 1)
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "## heading"), 2)
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "### heading"), 3)
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "#### heading"), 4)
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "##### heading"), 5)
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "###### heading"), 6)
    }

    func testHeadingLevelOfNonHeading() {
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "heading"))
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "h heading"))
        // A lone "#" is an empty level-1 heading in CommonMark, not a tag:
        // the marker requires only end-of-line or a space after the hashes.
        XCTAssertEqual(MarkdownFormatting.headingLevel(of: "#"), 1)
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "heading"))
    }

    // MARK: - Private helpers: lineBounds


    // MARK: - Private helpers: unwrap


    // MARK: - Private helpers: surroundingRange



    // MARK: - Private helpers: headingLevel(of: around:

    func testHeadingLevelOfNoDelimiter() {
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "just plain text"))
    }

    func testHeadingLevelOfWildcard() {
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "heading # something"))
    }
}
