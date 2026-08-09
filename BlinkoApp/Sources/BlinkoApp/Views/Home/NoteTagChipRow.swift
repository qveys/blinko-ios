import SwiftUI

/// A wrapping row of compact tag chips derived from a note's parsed tags.
///
/// Mirrors Blinko web's "tags are parsed from markdown" presentation: a small
/// capsule per tag with a leading `#`. The note's server-joined ``Note/tags``
/// is the source of truth; a note with no joined tags renders nothing rather
/// than inventing chips from raw `#hashtags`, so the row stays in sync with
/// what the server actually indexed.
///
/// Callers may pass a `tapAction` to turn the chips into filters (BLI-21's
/// tag filtering). With `nil` they are read-only affordances.
struct NoteTagChipRow: View {
    let tags: [Tag]
    /// Fired with the tapped tag's id, when the row is interactive.
    let tapAction: ((Tag) -> Void)?

    init(tags: [Tag], onTap tapAction: ((Tag) -> Void)? = nil) {
        self.tags = tags
        self.tapAction = tapAction
    }

    var body: some View {
        if tags.isEmpty {
            EmptyView()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { chips }
                VStack(alignment: .leading, spacing: 4) { chips }
            }
        }
    }

    private var chips: some View {
        ForEach(tags) { tag in
            TagChip(tag: tag, onTap: tapAction.map { action in
                { action(tag) }
            })
        }
    }
}

/// A single rounded tag chip: leading `#`, leaf name, primary-tinted capsule.
struct TagChip: View {
    let tag: Tag
    let onTap: (() -> Void)?

    init(tag: Tag, onTap: (() -> Void)? = nil) {
        self.tag = tag
        self.onTap = onTap
    }

    var body: some View {
        Text("#\(tag.displayName)")
            .font(.caption2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous).strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
            )
            .accessibilityLabel("Tag, \(tag.displayName)")
            .modifier(TappableIfPresent(onTap: onTap))
    }
}

/// Applies `onTapGesture` only when there is an action, so read-only chips
/// don't advertise interactivity to VoiceOver.
private struct TappableIfPresent: ViewModifier {
    let onTap: (() -> Void)?

    func body(content: Content) -> some View {
        if let onTap {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
        } else {
            content
        }
    }
}
