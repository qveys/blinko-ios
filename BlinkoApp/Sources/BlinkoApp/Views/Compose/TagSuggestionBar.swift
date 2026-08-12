import SwiftUI

/// The compact tag suggestion surface shown while a hashtag token is being
/// typed (BLI-39). Anchored above the keyboard rather than floated at the
/// caret — on a phone the keyboard accessory position is the reliable
/// "near the caret" placement the BLI-29 spec allows.
///
/// States, mirroring `tagSelectPop` on web:
/// - matching tags → tappable rows (`#full/path`), capped height ≈ 5 rows
/// - tags exist but none match → a single disabled `No tag found` row
/// - tags still loading → small inline spinner
/// Zero-tag accounts never see the bar at all (the view model publishes
/// nothing), so free typing of a brand-new tag is never interrupted.
struct TagSuggestionBar: View {
    let suggestions: [TagTypeahead.Suggestion]
    let showNoMatch: Bool
    let isLoading: Bool
    let onSelect: (TagTypeahead.Suggestion) -> Void

    /// ≈ 5 rows of 44 pt before the list scrolls (spec: about 5 on compact
    /// phones; scroll within the surface).
    private static let maxHeight: CGFloat = 224

    var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading tags…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
            } else if showNoMatch {
                Text("No tag found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityLabel("No matching tag")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(suggestions) { suggestion in
                            row(for: suggestion)
                        }
                    }
                }
                // Grow with content up to ~5 rows, then scroll within.
                .frame(height: min(CGFloat(suggestions.count) * 44, Self.maxHeight))
            }
        }
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private func row(for suggestion: TagTypeahead.Suggestion) -> some View {
        Button {
            onSelect(suggestion)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.subheadline)
                    .foregroundStyle(.tint)
                Text(suggestion.fullPath)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Tag, \(suggestion.fullPath)")
    }
}

#if DEBUG
#Preview("Suggestions") {
    let base = Date(timeIntervalSince1970: 1_725_000_000)
    let work = Tag(id: 1, name: "work", createdAt: base, updatedAt: base)
    let projects = Tag(id: 2, name: "projects", parent: 1, createdAt: base, updatedAt: base)
    return VStack {
        Spacer()
        TagSuggestionBar(
            suggestions: TagTypeahead.suggestions(matching: "", in: [work, projects]),
            showNoMatch: false,
            isLoading: false,
            onSelect: { _ in }
        )
    }
}

#Preview("No match") {
    VStack {
        Spacer()
        TagSuggestionBar(suggestions: [], showNoMatch: true, isLoading: false, onSelect: { _ in })
    }
}
#endif
