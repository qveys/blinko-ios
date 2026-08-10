import Foundation

/// Pure logic for the editor's hashtag typeahead (BLI-39): finding the
/// hashtag token being typed at the caret, filtering existing tags against
/// it, and splicing the chosen tag back into the content.
///
/// Everything here is UI-independent on purpose — the acceptance criteria
/// ask for the filtering + insertion logic to be testable without a view.
/// String positions are `String.Index`-safe but exposed as UTF-16 offsets,
/// because that is the currency `UITextView` selection ranges trade in.
enum TagTypeahead {

    /// The hashtag token the caret is currently inside, e.g. typing
    /// `Plan #wor|` yields `query == "wor"` spanning `#wor`.
    struct ActiveToken: Equatable {
        /// Text typed after `#`, with the `#` removed. Empty right after `#`.
        let query: String
        /// UTF-16 offset of the `#` character.
        let start: Int
        /// UTF-16 offset just past the last token character (usually the caret).
        let end: Int
    }

    /// Characters that terminate a hashtag token. Whitespace/newline ends the
    /// token (the spec dismisses suggestions on space/newline); a second `#`
    /// starts a new token rather than extending the old one.
    private static func isTokenCharacter(_ character: Character) -> Bool {
        !character.isWhitespace && !character.isNewline && character != "#"
    }

    /// Finds the hashtag token containing the caret, or `nil` when the caret
    /// is not inside one.
    ///
    /// Rules, mirroring web's `tagSelectPop` trigger:
    /// - Scan left from the caret for a `#` with no intervening whitespace.
    /// - The `#` must start the text or follow whitespace — `no#tag` inside a
    ///   word (URLs, markdown anchors) does not trigger suggestions.
    /// - The caret must sit at or before the token's end; a caret in the
    ///   middle of `#work` (e.g. `#wo|rk`) still counts, with the query cut
    ///   at the caret so suggestions match what was actually typed so far.
    static func activeToken(in text: String, caretUTF16Offset: Int) -> ActiveToken? {
        let utf16 = text.utf16
        guard caretUTF16Offset >= 0, caretUTF16Offset <= utf16.count else { return nil }
        guard let caretIndex = utf16.index(
            utf16.startIndex, offsetBy: caretUTF16Offset, limitedBy: utf16.endIndex
        ).flatMap({ $0.samePosition(in: text) }) else { return nil }

        // Scan left for the opening `#`.
        var hashIndex: String.Index?
        var cursor = caretIndex
        while cursor > text.startIndex {
            let previous = text.index(before: cursor)
            let character = text[previous]
            if character == "#" {
                hashIndex = previous
                break
            }
            guard isTokenCharacter(character) else { return nil }
            cursor = previous
        }
        guard let hash = hashIndex else { return nil }

        // `#` must begin the text or follow whitespace/newline.
        if hash > text.startIndex {
            let beforeHash = text[text.index(before: hash)]
            guard beforeHash.isWhitespace || beforeHash.isNewline else { return nil }
        }

        let queryStart = text.index(after: hash)
        let query = String(text[queryStart..<caretIndex])
        return ActiveToken(
            query: query,
            start: hash.utf16Offset(in: text),
            end: caretIndex.utf16Offset(in: text)
        )
    }

    /// A suggestion row: the tag plus its full slash-joined path, which is
    /// both the display label and the text inserted on selection.
    struct Suggestion: Identifiable, Equatable {
        let tag: Tag
        /// Full path from the root, e.g. `work/projects`.
        let fullPath: String
        var id: Int { tag.id }
    }

    /// Filters existing tags by the token's query, case-insensitively and
    /// path-aware: the query matches against each tag's full slash path, so
    /// `work/pro` matches `#work/projects` and a bare `pro` matches it too
    /// (substring match, same as web).
    ///
    /// Ordering: prefix matches on the full path first, then remaining
    /// substring matches; ties keep the service's tag order (the spec says
    /// not to invent an alphabetical order).
    static func suggestions(matching query: String, in tags: [Tag]) -> [Suggestion] {
        let all = tags.map { Suggestion(tag: $0, fullPath: fullPath(of: $0, in: tags)) }
        guard !query.isEmpty else { return all }
        let needle = query.lowercased()
        let matches = all.filter { $0.fullPath.lowercased().contains(needle) }
        // Stable partition: prefix matches keep their relative order ahead of
        // the rest, so `#wo` ranks `work` above `network`.
        let prefixed = matches.filter { $0.fullPath.lowercased().hasPrefix(needle) }
        let others = matches.filter { !$0.fullPath.lowercased().hasPrefix(needle) }
        return prefixed + others
    }

    /// The slash-joined path from the root to `tag`, resolved against the
    /// full `/tags/list` payload — Blinko stores one row per path segment
    /// (see ``Tag``), so `#work/projects` is the `projects` row walked up
    /// through its `parent` chain. Missing ancestors fall back to the leaf
    /// name; cycles (bad data) are broken by never visiting a row twice.
    private static func fullPath(of tag: Tag, in tags: [Tag]) -> String {
        let byId = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        var segments = [tag.name]
        var visited: Set<Int> = [tag.id]
        var current = tag
        while !current.isRoot, let parent = byId[current.parent], visited.insert(parent.id).inserted {
            segments.append(parent.name)
            current = parent
        }
        return segments.reversed().joined(separator: "/")
    }

    /// Result of inserting a suggestion: the rewritten content plus where the
    /// caret should land (just past the trailing space).
    struct Insertion: Equatable {
        let content: String
        /// UTF-16 offset for the new caret position.
        let caretUTF16Offset: Int
    }

    /// Replaces the active token with `#<fullPath> ` (trailing space included,
    /// per the acceptance criteria) and returns the new caret position.
    ///
    /// The replacement spans the *whole* token, not just up to the caret:
    /// accepting `#wo|rk` → `work/projects` should not leave a stray `rk`
    /// behind. Returns `nil` if the token's offsets don't fit `text` (stale
    /// token against newer content — the caller should just drop it).
    static func insert(_ suggestion: Suggestion, replacing token: ActiveToken, in text: String) -> Insertion? {
        let utf16 = text.utf16
        guard token.start >= 0, token.start < utf16.count else { return nil }
        guard let hashIndex = utf16.index(
            utf16.startIndex, offsetBy: token.start, limitedBy: utf16.endIndex
        ).flatMap({ $0.samePosition(in: text) }), text[hashIndex] == "#" else { return nil }

        // Extend past the caret to the real end of the token.
        var tokenEnd = text.index(after: hashIndex)
        while tokenEnd < text.endIndex, isTokenCharacter(text[tokenEnd]) {
            tokenEnd = text.index(after: tokenEnd)
        }

        let replacement = "#\(suggestion.fullPath) "
        var content = text
        content.replaceSubrange(hashIndex..<tokenEnd, with: replacement)
        return Insertion(
            content: content,
            caretUTF16Offset: token.start + replacement.utf16.count
        )
    }
}
