import Foundation

/// A block-level element of a note's markdown content.
///
/// Blinko web renders notes through a standard CommonMark pipeline; on iOS,
/// Foundation's `AttributedString(markdown:)` covers *inline* syntax (bold,
/// italic, code spans, links) but flattens block structure. This parser
/// restores just the block shapes the web app's basic notes actually use —
/// headings, lists, quotes, fenced code, thematic breaks — and leaves inline
/// rendering to `AttributedString`. Anything fancier (tables, footnotes,
/// custom extensions) is deliberately out of scope: BLI-20 targets web
/// parity, not a full CommonMark engine.
enum MarkdownBlock: Equatable, Sendable {
    /// `# Title` through `###### Title`. Level is clamped to 1...6.
    case heading(level: Int, text: String)
    /// A run of plain lines, joined with newlines. Inline markdown intact.
    case paragraph(text: String)
    /// Consecutive `-` / `*` / `+` items. Item text keeps inline markdown.
    case bulletList(items: [String])
    /// Consecutive `1.` / `2)` items, renumbered from 1 for display.
    case orderedList(items: [String])
    /// Consecutive `>` lines, joined with newlines, markers stripped.
    case blockquote(text: String)
    /// A fenced ``` block. Content is verbatim — no inline parsing.
    case codeBlock(language: String?, code: String)
    /// `---`, `***`, or `___` on its own line.
    case thematicBreak
}

enum MarkdownBlockParser {
    /// Splits markdown source into block elements.
    ///
    /// Line-oriented single pass. Blank lines terminate the current block;
    /// an unterminated code fence runs to the end of input (CommonMark's
    /// behaviour) so a half-typed fence never swallows the parse.
    static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        // Keep empty lines: they delimit blocks and matter inside code fences.
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var index = 0
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                index += 1
                continue
            }

            if let fence = fenceInfo(trimmed) {
                var code: [String] = []
                index += 1
                while index < lines.count,
                      fenceInfo(lines[index].trimmingCharacters(in: .whitespaces))?.language.isEmpty != true {
                    code.append(lines[index])
                    index += 1
                }
                index += 1 // Skip the closing fence (or run past the end).
                blocks.append(.codeBlock(
                    language: fence.language.isEmpty ? nil : fence.language,
                    code: code.joined(separator: "\n")
                ))
                continue
            }

            if isThematicBreak(trimmed) {
                blocks.append(.thematicBreak)
                index += 1
                continue
            }

            if let heading = headingBlock(trimmed) {
                blocks.append(heading)
                index += 1
                continue
            }

            if bulletItemText(trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = bulletItemText(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            if orderedItemText(trimmed) != nil {
                var items: [String] = []
                while index < lines.count,
                      let item = orderedItemText(lines[index].trimmingCharacters(in: .whitespaces)) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            if trimmed.hasPrefix(">") {
                var quoted: [String] = []
                while index < lines.count {
                    let quoteLine = lines[index].trimmingCharacters(in: .whitespaces)
                    guard quoteLine.hasPrefix(">") else { break }
                    quoted.append(stripQuoteMarker(quoteLine))
                    index += 1
                }
                blocks.append(.blockquote(text: quoted.joined(separator: "\n")))
                continue
            }

            // Paragraph: absorb lines until a blank line or another block start.
            var paragraph: [String] = []
            while index < lines.count {
                let paragraphLine = lines[index].trimmingCharacters(in: .whitespaces)
                guard !paragraphLine.isEmpty,
                      fenceInfo(paragraphLine) == nil,
                      headingBlock(paragraphLine) == nil,
                      bulletItemText(paragraphLine) == nil,
                      orderedItemText(paragraphLine) == nil,
                      !paragraphLine.hasPrefix(">"),
                      !isThematicBreak(paragraphLine)
                else { break }
                paragraph.append(paragraphLine)
                index += 1
            }
            blocks.append(.paragraph(text: paragraph.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: - Line classification

    private struct Fence {
        var language: String
    }

    /// Non-nil when the line opens (or closes) a ``` fence. The remainder of
    /// the line after the backticks is the info string (language tag); a
    /// closing fence has an empty one.
    private static func fenceInfo(_ line: String) -> Fence? {
        guard line.hasPrefix("```") else { return nil }
        let info = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        return Fence(language: info)
    }

    private static func headingBlock(_ line: String) -> MarkdownBlock? {
        guard line.hasPrefix("#") else { return nil }
        let marker = line.prefix(while: { $0 == "#" })
        // `####### seven` and `#hashtag` are paragraph text, not headings.
        guard marker.count <= 6 else { return nil }
        let rest = line.dropFirst(marker.count)
        guard rest.first == " " || rest.isEmpty else { return nil }
        let text = rest.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return .heading(level: marker.count, text: text)
    }

    private static func bulletItemText(_ line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let text = line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
            if !text.isEmpty { return text }
        }
        return nil
    }

    private static func orderedItemText(_ line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        let text = rest.dropFirst(2).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func stripQuoteMarker(_ line: String) -> String {
        var rest = line.dropFirst() // The leading ">".
        if rest.first == " " { rest = rest.dropFirst() }
        return String(rest)
    }

    private static func isThematicBreak(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        for symbol: Character in ["-", "*", "_"] where line.allSatisfy({ $0 == symbol }) {
            return true
        }
        return false
    }
}

// MARK: - Inline rendering

extension AttributedString {
    /// Parses inline markdown (bold, italic, code, links), falling back to
    /// the literal text when Foundation's parser rejects the input — a note
    /// must never fail to display because of malformed markup.
    static func markdownInline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}
