import Foundation

/// The markdown transforms behind the editor's formatting toolbar.
///
/// Pure string math, deliberately kept out of the view and the view model so
/// the awkward cases — toggling a style back off, applying to an empty
/// selection, a heading that already has a different level — are unit-testable
/// without a running `TextEditor`.
///
/// Scope matches BLI-60's "toolbar minimal" guard: inline emphasis (bold,
/// italic, code) and line-level headings. No lists, links, or tables.
enum MarkdownFormatting {
    /// Inline styles that wrap a selection in the same delimiter on both sides.
    enum InlineStyle: String, CaseIterable {
        case bold = "**"
        case italic = "*"
        case code = "`"

        var delimiter: String { rawValue }
    }

    /// The result of a toolbar action: the new document plus where the
    /// selection should land, so the caller can keep the caret sensible.
    struct Result: Equatable {
        var text: String
        /// Selection in the *new* text, as a UTF-16-agnostic character range.
        var selection: Range<String.Index>

        /// Convenience for tests and callers that think in offsets.
        func selectedOffsets() -> ClosedRange<Int> {
            let lower = text.distance(from: text.startIndex, to: selection.lowerBound)
            let upper = text.distance(from: text.startIndex, to: selection.upperBound)
            return lower...upper
        }
    }

    // MARK: - Inline emphasis

    /// Wraps `selection` in the style's delimiter, or unwraps it when the
    /// selection is already wrapped — the toolbar button is a toggle, matching
    /// how every markdown editor users have met behaves.
    ///
    /// With an empty selection the delimiters are still inserted and the caret
    /// lands between them, so tapping **B** then typing produces bold text.
    static func toggleInline(
        _ style: InlineStyle,
        in text: String,
        selection: Range<String.Index>
    ) -> Result {
        let delimiter = style.delimiter
        let selected = String(text[selection])

        if let unwrapped = unwrap(selected, delimiter: delimiter) {
            // Selection includes the delimiters: "**bold**" -> "bold".
            let replaced = text.replacingCharacters(in: selection, with: unwrapped)
            let start = replaced.index(
                replaced.startIndex,
                offsetBy: text.distance(from: text.startIndex, to: selection.lowerBound)
            )
            let end = replaced.index(start, offsetBy: unwrapped.count)
            return Result(text: replaced, selection: start..<end)
        }

        if let outer = surroundingRange(of: delimiter, around: selection, in: text) {
            // Delimiters sit just outside the selection: |bold| inside **…**.
            let replaced = text.replacingCharacters(in: outer, with: selected)
            let start = replaced.index(
                replaced.startIndex,
                offsetBy: text.distance(from: text.startIndex, to: outer.lowerBound)
            )
            let end = replaced.index(start, offsetBy: selected.count)
            return Result(text: replaced, selection: start..<end)
        }

        let wrapped = delimiter + selected + delimiter
        let replaced = text.replacingCharacters(in: selection, with: wrapped)
        let prefixCount = text.distance(from: text.startIndex, to: selection.lowerBound)
        let start = replaced.index(replaced.startIndex, offsetBy: prefixCount + delimiter.count)
        let end = replaced.index(start, offsetBy: selected.count)
        return Result(text: replaced, selection: start..<end)
    }

    // MARK: - Headings

    /// Applies `level` (1–6) to every line the selection touches.
    ///
    /// Re-applying the level a line already has strips it, so the button
    /// toggles; applying a *different* level replaces the existing marker
    /// rather than stacking `#`s.
    static func toggleHeading(
        level: Int,
        in text: String,
        selection: Range<String.Index>
    ) -> Result {
        let clamped = min(max(level, 1), 6)
        let marker = String(repeating: "#", count: clamped)
        let lineRange = lineBounds(containing: selection, in: text)
        let block = String(text[lineRange])

        // Only toggle off when *every* touched line already has this level;
        // a mixed selection should normalize to the requested level instead.
        let lines = block.components(separatedBy: "\n")
        let allAtLevel = lines.allSatisfy { headingLevel(of: $0) == clamped }

        let rewritten = lines.map { line -> String in
            let body = strippedHeading(from: line)
            return allAtLevel ? body : (body.isEmpty ? marker + " " : marker + " " + body)
        }
        .joined(separator: "\n")

        let replaced = text.replacingCharacters(in: lineRange, with: rewritten)
        let start = replaced.index(
            replaced.startIndex,
            offsetBy: text.distance(from: text.startIndex, to: lineRange.lowerBound)
        )
        let end = replaced.index(start, offsetBy: rewritten.count)
        return Result(text: replaced, selection: start..<end)
    }

    /// The heading level of a line, or `nil` when it isn't a heading.
    /// Requires the space after the `#`s that CommonMark requires — `#tag` is
    /// a Blinko tag, not an H1.
    static func headingLevel(of line: String) -> Int? {
        let trimmed = line.drop { $0 == " " }
        let hashes = trimmed.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = trimmed.dropFirst(hashes.count)
        guard rest.isEmpty || rest.first == " " else { return nil }
        return hashes.count
    }

    // MARK: - Private helpers

    /// Removes a leading heading marker from a line, leaving the body.
    private static func strippedHeading(from line: String) -> String {
        guard headingLevel(of: line) != nil else { return line }
        return String(line.drop { $0 == " " }.drop { $0 == "#" }.drop { $0 == " " })
    }

    /// `"**bold**"` -> `"bold"`; `nil` when the string isn't wrapped.
    private static func unwrap(_ string: String, delimiter: String) -> String? {
        guard string.count >= delimiter.count * 2,
              string.hasPrefix(delimiter),
              string.hasSuffix(delimiter)
        else { return nil }
        return String(string.dropFirst(delimiter.count).dropLast(delimiter.count))
    }

    /// The range covering `selection` *plus* the delimiters immediately
    /// outside it, when they are present on both sides.
    private static func surroundingRange(
        of delimiter: String,
        around selection: Range<String.Index>,
        in text: String
    ) -> Range<String.Index>? {
        let count = delimiter.count
        guard text.distance(from: text.startIndex, to: selection.lowerBound) >= count,
              text.distance(from: selection.upperBound, to: text.endIndex) >= count
        else { return nil }

        let before = text.index(selection.lowerBound, offsetBy: -count)
        let after = text.index(selection.upperBound, offsetBy: count)
        guard text[before..<selection.lowerBound] == delimiter,
              text[selection.upperBound..<after] == delimiter
        else { return nil }
        return before..<after
    }

    /// Expands a selection outward to whole lines, so heading markers land at
    /// line starts even when the user selected mid-word.
    private static func lineBounds(
        containing selection: Range<String.Index>,
        in text: String
    ) -> Range<String.Index> {
        var start = selection.lowerBound
        while start > text.startIndex {
            let previous = text.index(before: start)
            if text[previous] == "\n" { break }
            start = previous
        }

        var end = selection.upperBound
        while end < text.endIndex, text[end] != "\n" {
            end = text.index(after: end)
        }
        return start..<end
    }
}
