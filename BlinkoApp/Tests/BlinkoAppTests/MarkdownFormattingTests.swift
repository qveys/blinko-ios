import XCTest
@testable import BlinkoApp

@MainActor
final class MarkdownFormattingTests: XCTestCase {

    // MARK: - Inline: bold

    func testToggleBold() {
        let fmt = MarkdownFormatting()
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "**hello world**")
        XCTAssertEqual(result.selection.lowerBound.distance(to: result.text.startIndex), 2)
        XCTAssertEqual(result.selection.upperBound.distance(to: result.text.startIndex), 7)
    }

    func testToggleBoldTwice() {
        // Toggle back off: **bold** -> bold
        let fmt = MarkdownFormatting()
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)
        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "bold")
    }

    func testToggleBoldEmptySelection() {
        // Empty selection still inserts delimiters
        let fmt = MarkdownFormatting()
        let text = "hello"
        let selection: Range<String.Index> = text.startIndex..<text.endIndex

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "**hello**")
        // Selection should be between the delimiters
        XCTAssertEqual(result.selection.lowerBound.distance(to: result.text.startIndex), 2)
        XCTAssertEqual(result.selection.upperBound.distance(to: result.text.startIndex), 6)
    }

    func testToggleBoldAtEnd() {
        // Selection at the end
        let fmt = MarkdownFormatting()
        let text = "world"
        let selection = text.index(text.startIndex, offsetBy: 5)..<text.endIndex
        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "world**")
        XCTAssertEqual(result.selection.lowerBound.distance(to: result.text.startIndex), 5)
        XCTAssertEqual(result.selection.upperBound.distance(to: result.text.startIndex), 10)
    }

    // MARK: - Inline: italic

    func testToggleItalic() {
        let fmt = MarkdownFormatting()
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleInline(.italic, in: text, selection: selection)
        XCTAssertEqual(result.text, "hello*world*")
    }

    // MARK: - Inline: code

    func testToggleCode() {
        let fmt = MarkdownFormatting()
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleInline(.code, in: text, selection: selection)
        XCTAssertEqual(result.text, "hello`world`")
    }

    // MARK: - Inline: toggle off

    func testToggleInlineUnwraps() {
        let fmt = MarkdownFormatting()
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "bold")
    }

    // MARK: - Inline: mixed case

    func testToggleBoldOnAlreadyFormatted() {
        let fmt = MarkdownFormatting()
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)

        let result = MarkdownFormatting.toggleInline(.bold, in: text, selection: selection)
        XCTAssertEqual(result.text, "bold")
    }

    // MARK: - Heading

    func testToggleHeadingLevel1() {
        let fmt = MarkdownFormatting()
        let text = "hello world"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 5)

        let result = MarkdownFormatting.toggleHeading(level: 1, in: text, selection: selection)
        XCTAssertEqual(result.text, "# hello world")
    }

    func testToggleHeadingLevel1ThenLevel2() {
        let fmt = MarkdownFormatting()
        let text = "# heading"
        let selection = text.index(text.startIndex, offsetBy: 1)..<text.index(text.startIndex, offsetBy: 10)

        let result = MarkdownFormatting.toggleHeading(level: 2, in: text, selection: selection)
        XCTAssertEqual(result.text, "## heading")
    }

    func testToggleHeadingAlreadyLevel1() {
        // Applying level 1 to an already-level-1 heading re-strips to level 1 (idempotent)
        let fmt = MarkdownFormatting()
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
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "#"))
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "heading"))
    }

    // MARK: - Private helpers: lineBounds

    func testLineBounds() {
        let text = "line1\nline2"
        let selection = text.index(text.startIndex, offsetBy: 6)..<text.index(text.startIndex, offsetBy: 11)
        // Should expand to whole lines
        let result = MarkdownFormatting.lineBounds(containing: selection, in: text)
        XCTAssertEqual(result.lowerBound.distance(to: text.startIndex), 0)
        XCTAssertEqual(result.upperBound.distance(to: text.startIndex), 12)
    }

    // MARK: - Private helpers: unwrap

    func testUnwrap() {
        XCTAssertEqual(MarkdownFormatting.unwrap("**bold**", delimiter: "**"), "bold")
        XCTAssertEqual(MarkdownFormatting.unwrap("**bold**extra", delimiter: "**"), "bold**extra")
        XCTAssertNil(MarkdownFormatting.unwrap("**bold", delimiter: "**"))
    }

    // MARK: - Private helpers: surroundingRange

    func testSurroundingRange() {
        let text = "|**bold**|"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)
        let result = MarkdownFormatting.surroundingRange(of: "**", around: selection, in: text)
        XCTAssertEqual(result.lowerBound.distance(to: text.startIndex), 1)
        XCTAssertEqual(result.upperBound.distance(to: text.startIndex), 11)
    }

    func testSurroundingRangeDoesNotMatch() {
        let text = "**bold**"
        let selection = text.index(text.startIndex, offsetBy: 2)..<text.index(text.startIndex, offsetBy: 7)
        let result = MarkdownFormatting.surroundingRange(of: "**", around: selection, in: text)
        XCTAssertNil(result)
    }

    // MARK: - Private helpers: headingLevel(of: around:

    func testHeadingLevelOfNoDelimiter() {
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "just plain text"))
    }

    func testHeadingLevelOfWildcard() {
        XCTAssertNil(MarkdownFormatting.headingLevel(of: "heading # something"))
    }
}
