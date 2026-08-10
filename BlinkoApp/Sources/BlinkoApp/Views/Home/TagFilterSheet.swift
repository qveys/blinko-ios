import SwiftUI

/// The tag filter picker: Blinko web's sidebar tag tree in mobile sheet form.
///
/// Strictly a *filter* surface — no rename, delete, sort, or any taxonomy
/// management (BLI-29 scope guard). Rows show the hashtag icon (or the tag's
/// own icon), leaf name, child count and chevron for parents; the selected
/// tag row is tinted with the primary color, matching web's selected sidebar
/// item. Tapping a tag applies it as the note-list filter and dismisses.
struct TagFilterSheet: View {
    @ObservedObject var viewModel: TagFilterViewModel
    /// The currently applied filter, so the matching row renders selected
    /// and an `All notes` row appears to clear it.
    let activeFilter: ActiveTagFilter?
    /// Fired with the chosen filter, or `nil` for "All notes".
    let onSelect: (ActiveTagFilter?) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.tree.isEmpty, viewModel.isLoading || !viewModel.hasLoaded {
                    loadingState
                } else if viewModel.loadFailed, viewModel.tree.isEmpty {
                    errorState
                } else if viewModel.isEmpty {
                    emptyState
                } else {
                    tagList
                }
            }
            .navigationTitle("Filter by Tag")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await viewModel.loadTags() }
    }

    private var tagList: some View {
        List {
            // Escape hatch back to the unfiltered list, only when a filter
            // is applied (per spec).
            if activeFilter != nil {
                Button {
                    onSelect(nil)
                } label: {
                    Label("All notes", systemImage: "tray.full")
                }
                .accessibilityHint("Clears the tag filter")
            }
            ForEach(viewModel.visibleRows, id: \.node.id) { row in
                TagFilterRow(
                    node: row.node,
                    depth: row.depth,
                    isSelected: row.node.id == activeFilter?.id,
                    isExpanded: viewModel.isExpanded(row.node),
                    onTap: {
                        onSelect(ActiveTagFilter(id: row.node.id, fullPath: row.node.fullPath))
                    },
                    onToggleExpand: { viewModel.toggleExpanded(row.node) }
                )
            }
        }
        .listStyle(.plain)
    }

    /// Skeleton rows under the title while the first load is in flight.
    private var loadingState: some View {
        List {
            ForEach(0..<5, id: \.self) { _ in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.secondary.opacity(0.15)).frame(width: 18, height: 18)
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(height: 14)
                }
                .redacted(reason: .placeholder)
            }
        }
        .listStyle(.plain)
    }

    private var errorState: some View {
        ContentUnavailableView {
            Label("Couldn't load tags", systemImage: "exclamationmark.triangle")
        } description: {
            Text(viewModel.errorMessage.isEmpty ? "Check your connection and try again." : viewModel.errorMessage)
        } actions: {
            Button("Retry") {
                Task { await viewModel.loadTags() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No tags yet", systemImage: "number")
        } description: {
            Text("Tags appear after notes contain hashtags.")
        }
    }
}

/// One row of the tag tree: indentation by depth, hashtag/custom icon, name,
/// child count and expand chevron for parents.
private struct TagFilterRow: View {
    let node: TagTreeNode
    let depth: Int
    let isSelected: Bool
    let isExpanded: Bool
    let onTap: () -> Void
    let onToggleExpand: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            Text(node.tag.name)
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if node.hasChildren {
                Text("\(node.childCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                // The chevron is its own tap target so expanding does not
                // also apply the filter.
                Button(action: onToggleExpand) {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExpanded ? "Collapse" : "Expand")
            }
        }
        .padding(.leading, CGFloat(depth) * 20)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var icon: some View {
        if node.tag.icon.isEmpty {
            Image(systemName: "number")
                .font(.subheadline)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
        } else {
            Text(node.tag.icon)
                .font(.subheadline)
        }
    }

    private var accessibilityLabel: String {
        if node.hasChildren {
            let state = isExpanded ? "expanded" : "collapsed"
            return "\(node.tag.name), \(node.childCount) child tags, \(state)"
        }
        return "Tag, \(node.fullPath)"
    }
}

#if DEBUG
#Preview("Tag filter sheet") {
    TagFilterSheet(
        viewModel: TagFilterViewModel(tagService: MockTagService()),
        activeFilter: ActiveTagFilter(id: 3, fullPath: "work"),
        onSelect: { _ in }
    )
}

#Preview("Tag filter — error") {
    TagFilterSheet(
        viewModel: TagFilterViewModel(
            tagService: MockTagService(error: APIError.transport("offline"))
        ),
        activeFilter: nil,
        onSelect: { _ in }
    )
}

#Preview("Tag filter — empty") {
    TagFilterSheet(
        viewModel: TagFilterViewModel(tagService: MockTagService(tags: [])),
        activeFilter: nil,
        onSelect: { _ in }
    )
}
#endif
