import SwiftUI

/// A single note card in the home feed.
///
/// Layout, top to bottom:
/// - status indicators (pinned / todo / attachments) + relative time
/// - title: first non-empty line, heading markers stripped, semibold
/// - snippet: remaining lines, two-line limit, secondary
/// - tag chips, derived from the note's parsed tags
///
/// The presentation follows Blinko web: ordering is server-driven (`orderBy:
/// desc` on `updatedAt`), the title is the first line, and tags are compact
/// chips below the excerpt. Tapping the row is handled by the parent list.
struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if !note.displayTitle.isEmpty {
                Text(note.displayTitle)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
            }

            if !note.displaySnippet.isEmpty {
                Text(note.displaySnippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !note.tags.isEmpty {
                NoteTagChipRow(tags: note.tags)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Top status row: badges on the left, timestamp on the right.
    private var header: some View {
        HStack(spacing: 6) {
            if note.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Pinned")
            }
            if note.isTodo {
                Label("Todo", systemImage: "checklist")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Todo")
            }
            if note.hasAttachments {
                Label("Has attachment", systemImage: "paperclip")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Has attachment")
            }
            Spacer(minLength: 0)
            Text(note.updatedAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        var parts: [String] = []
        if note.isPinned { parts.append("Pinned") }
        if !note.displayTitle.isEmpty { parts.append(note.displayTitle) } else { parts.append("Untitled note") }
        if !note.displaySnippet.isEmpty { parts.append(note.displaySnippet) }
        if !note.tags.isEmpty { parts.append("Tags: " + note.tags.map(\.displayName).joined(separator: ", ")) }
        return parts.joined(separator: ", ")
    }
}

#if DEBUG
#Preview("Note row variants") {
    let base = Date(timeIntervalSince1970: 1_725_000_000)
    let note = Note(
        id: 1,
        content: "# Quarter plan\n\nShip the notes list before the freeze.\nMore detail here.",
        type: .note,
        isTop: true,
        createdAt: base,
        updatedAt: base,
        attachments: [
            Attachment(id: 1, name: "photo.png", path: "/api/file/photo.png", size: 2048, type: "image/png", createdAt: base, updatedAt: base)
        ],
        tagRelations: [
            TagRelation(noteId: 1, tagId: 7, tag: Tag(id: 7, name: "projects", parent: 3, createdAt: base, updatedAt: base))
        ]
    )
    let plain = Note(id: 2, content: "Just a single line.", createdAt: base, updatedAt: base)
    let empty = Note(id: 3, content: "", createdAt: base, updatedAt: base)

    return ScrollView {
        VStack(spacing: 12) {
            NoteRowView(note: note)
            Divider()
            NoteRowView(note: plain)
            Divider()
            NoteRowView(note: empty)
        }
        .padding()
    }
    .frame(height: 320)
}
#endif
