import SwiftUI

/// Renders a note's markdown as native SwiftUI views.
///
/// Block structure comes from ``MarkdownBlockParser``; inline styling within
/// each block (bold, italic, code spans, links) is handled by
/// `AttributedString(markdown:)`. This mirrors what Blinko web shows for
/// basic notes — headings, lists, quotes, fenced code — without pulling in a
/// web view or a third-party markdown package.
struct MarkdownContentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(MarkdownBlockParser.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(AttributedString.markdownInline(text))
                .font(headingFont(level))
                .textSelection(.enabled)

        case .paragraph(let text):
            Text(AttributedString.markdownInline(text))
                .font(.body)
                .textSelection(.enabled)

        case .bulletList(let items):
            listView(items: items) { _ in
                Text("•")
            }

        case .orderedList(let items):
            listView(items: items) { index in
                // Renumbered from 1: display order wins over source numbers,
                // which is how CommonMark renderers (and Blinko web) behave.
                Text("\(index + 1).")
                    .monospacedDigit()
            }

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.4))
                    .frame(width: 3)
                Text(AttributedString.markdownInline(text))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

        case .thematicBreak:
            Divider()
        }
    }

    private func listView(items: [String], marker: @escaping (Int) -> Text) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    marker(index)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Text(AttributedString.markdownInline(item))
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title.weight(.bold)
        case 2: return .title2.weight(.bold)
        case 3: return .title3.weight(.semibold)
        default: return .headline
        }
    }
}

#if DEBUG
#Preview("Markdown content") {
    ScrollView {
        MarkdownContentView(markdown: """
        # Quarter plan

        Ship the notes **list** before the freeze. See [Blinko](https://blinko.example).

        ## Steps
        - Build the editor
        - Wire *markdown* rendering
        1. First
        2. Second

        > A quote to remember.

        ```swift
        let done = true
        ```

        ---

        Tail paragraph.
        """)
        .padding()
    }
}
#endif
