import XCTest
@testable import BlinkoApp

/// Tests for the block-level markdown parser behind the note detail screen.
final class MarkdownBlockParserTests: XCTestCase {
    // MARK: - Headings

    func testParsesHeadingLevels() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("# One\n\n## Two\n\n###### Six"),
            [
                .heading(level: 1, text: "One"),
                .heading(level: 2, text: "Two"),
                .heading(level: 6, text: "Six"),
            ]
        )
    }

    func testSevenHashesIsNotAHeading() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("####### seven"),
            [.paragraph(text: "####### seven")]
        )
    }

    func testHashtagWithoutSpaceIsNotAHeading() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("#hashtag"),
            [.paragraph(text: "#hashtag")]
        )
    }

    // MARK: - Paragraphs

    func testAdjacentLinesFormOneParagraph() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("line one\nline two\n\nsecond paragraph"),
            [
                .paragraph(text: "line one\nline two"),
                .paragraph(text: "second paragraph"),
            ]
        )
    }

    func testEmptyInputParsesToNothing() {
        XCTAssertEqual(MarkdownBlockParser.parse(""), [])
        XCTAssertEqual(MarkdownBlockParser.parse("\n  \n"), [])
    }

    // MARK: - Lists

    func testBulletListGroupsConsecutiveItems() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("- a\n* b\n+ c"),
            [.bulletList(items: ["a", "b", "c"])]
        )
    }

    func testOrderedListAcceptsDotAndParen() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("1. first\n2) second"),
            [.orderedList(items: ["first", "second"])]
        )
    }

    func testListEndsAtParagraph() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("- a\n- b\ntail text"),
            [
                .bulletList(items: ["a", "b"]),
                .paragraph(text: "tail text"),
            ]
        )
    }

    // MARK: - Blockquote

    func testBlockquoteJoinsLinesAndStripsMarkers() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("> line one\n> line two"),
            [.blockquote(text: "line one\nline two")]
        )
    }

    // MARK: - Code fences

    func testFencedCodeBlockKeepsContentVerbatim() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("```swift\nlet a = 1\n\n# not a heading\n```"),
            [.codeBlock(language: "swift", code: "let a = 1\n\n# not a heading")]
        )
    }

    func testFenceWithoutLanguage() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("```\nplain\n```"),
            [.codeBlock(language: nil, code: "plain")]
        )
    }

    func testUnterminatedFenceRunsToEnd() {
        XCTAssertEqual(
            MarkdownBlockParser.parse("```\nstill code\nmore"),
            [.codeBlock(language: nil, code: "still code\nmore")]
        )
    }

    // MARK: - Thematic break

    func testThematicBreakVariants() {
        XCTAssertEqual(MarkdownBlockParser.parse("---"), [.thematicBreak])
        XCTAssertEqual(MarkdownBlockParser.parse("***"), [.thematicBreak])
        XCTAssertEqual(MarkdownBlockParser.parse("___"), [.thematicBreak])
        // Two dashes is just text.
        XCTAssertEqual(MarkdownBlockParser.parse("--"), [.paragraph(text: "--")])
    }

    // MARK: - Mixed document

    func testTypicalNoteParsesInOrder() {
        let markdown = """
        # Title

        Intro paragraph.

        - one
        - two

        > quoted

        ```js
        x()
        ```

        ---

        Tail.
        """
        XCTAssertEqual(
            MarkdownBlockParser.parse(markdown),
            [
                .heading(level: 1, text: "Title"),
                .paragraph(text: "Intro paragraph."),
                .bulletList(items: ["one", "two"]),
                .blockquote(text: "quoted"),
                .codeBlock(language: "js", code: "x()"),
                .thematicBreak,
                .paragraph(text: "Tail."),
            ]
        )
    }

    // MARK: - Inline fallback

    func testInlineRenderingNeverFails() {
        // Malformed markup must fall back to literal text, not crash or drop.
        let rendered = AttributedString.markdownInline("broken [link(")
        XCTAssertFalse(String(rendered.characters).isEmpty)
    }
}
