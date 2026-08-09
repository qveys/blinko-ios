import Foundation

// MARK: - Display text

extension Note {
    /// The first non-empty line, with leading markdown heading markers (`#`)
    /// stripped. Blinko web treats this as the note's title.
    ///
    /// An empty string when the note has no content yet — the row then falls
    /// back to a localized "Untitled" placeholder so the cell never collapses
    /// to zero height.
    var displayTitle: String {
        firstLine.flatMap { Self.stripHeadingMarkers($0) }
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? ""
    }

    /// Everything after the title line, trimmed of surrounding whitespace.
    /// Empty when the note is a single line (or empty).
    var displaySnippet: String {
        guard let range = content.range(of: "\n") else { return "" }
        let rest = content[range.upperBound...]
        let trimmed = rest.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "" : trimmed
    }

    /// `true` when the note has no usable text to show.
    var isEmpty: Bool {
        content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The first non-empty line of the content, before any heading stripping.
    private var firstLine: String? {
        content
            .split(omittingEmptySubsequences: true, whereSeparator: { $0.isNewline })
            .map(String.init)
            .first
    }

    /// Removes leading `#` ATX heading markers and the space after them.
    /// `# Title` → `Title`; `## Sub` → `Sub`. Leaves body text untouched.
    private static func stripHeadingMarkers(_ line: String) -> String {
        var rest = line
        while rest.first == "#" {
            rest.removeFirst()
        }
        // Drop the single space Markdown requires between markers and text.
        if rest.first == " " { rest.removeFirst() }
        return rest
    }
}

// MARK: - Presentation flags

extension Note {
    /// Pinned to the top of the list — Blinko's `isTop`.
    var isPinned: Bool { isTop }

    /// Whether the note carries any attachments. Drives a paperclip indicator.
    var hasAttachments: Bool { !attachments.isEmpty }

    /// Whether this is a checklist note. Blinko's `type == 2`.
    var isTodo: Bool { type == .todo }

    /// Inline `#tag` path labels parsed from content, for a lightweight chip row
    /// that mirrors the web "tags parsed from markdown" behaviour.
    ///
    /// The server-joined `tags` property is the source of truth for the chip row
    /// shown in the UI; this exists so a note that has not been upserted yet
    /// (e.g. a fresh draft) still renders its hashtags. Returns unique, ordered
    /// by first appearance.
    var inlineHashtags: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for word in content.split(whereSeparator: { $0.isWhitespace || $0.isNewline }) {
            guard word.hasPrefix("#"), word.count > 1 else { continue }
            // Trim trailing punctuation so "#work." links the "work" tag.
            let label = word
                .dropFirst()
                .trimmingCharacters(in: .punctuationCharacters)
            guard !label.isEmpty, !seen.contains(label) else { continue }
            seen.insert(label)
            result.append(label)
        }
        return result
    }
}
