import Foundation

/// A node of the hierarchical tag tree shown in the tag filter sheet.
///
/// The server stores tags as flat rows linked by `parent` ids (see ``Tag``);
/// this is the assembled tree the UI actually renders: children nested under
/// their parent, each node carrying its full slash-joined path so the filter
/// chip can show `#work/projects` even though the row's `name` is just the
/// leaf segment.
struct TagTreeNode: Identifiable, Equatable, Sendable {
    let tag: Tag
    /// Full path from the root, e.g. `work/projects` for the `projects` row.
    let fullPath: String
    var children: [TagTreeNode]

    var id: Int { tag.id }
    var hasChildren: Bool { !children.isEmpty }
    var childCount: Int { children.count }
}

enum TagTreeBuilder {
    /// Assembles the flat `/tags/list` payload into a tree.
    ///
    /// - Roots are tags with `parent == 0` — plus any tag whose parent id is
    ///   missing from the payload, so a partially-synced list never hides
    ///   tags from the UI (same policy as `groupedByParent()`).
    /// - Siblings sort by `sortOrder`, falling back to payload order — the
    ///   spec says to preserve hierarchy order from the API, not to invent
    ///   an alphabetical one.
    /// - Cycles (bad data) are broken by never visiting a tag twice.
    static func buildTree(from tags: [Tag]) -> [TagTreeNode] {
        let byId = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let payloadIndex = Dictionary(
            uniqueKeysWithValues: tags.enumerated().map { ($0.element.id, $0.offset) }
        )
        func siblingOrder(_ lhs: Tag, _ rhs: Tag) -> Bool {
            if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
            return payloadIndex[lhs.id, default: 0] < payloadIndex[rhs.id, default: 0]
        }
        let childrenByParent = Dictionary(grouping: tags.filter { !$0.isRoot && byId[$0.parent] != nil }, by: \.parent)
        let roots = tags.filter { $0.isRoot || byId[$0.parent] == nil }

        var visited = Set<Int>()
        func node(for tag: Tag, pathPrefix: String) -> TagTreeNode? {
            guard visited.insert(tag.id).inserted else { return nil }
            let fullPath = pathPrefix.isEmpty ? tag.name : "\(pathPrefix)/\(tag.name)"
            let children = (childrenByParent[tag.id] ?? [])
                .sorted(by: siblingOrder)
                .compactMap { node(for: $0, pathPrefix: fullPath) }
            return TagTreeNode(tag: tag, fullPath: fullPath, children: children)
        }

        return roots
            .sorted(by: siblingOrder)
            .compactMap { node(for: $0, pathPrefix: "") }
    }
}

extension Tag {
    /// The slash-joined path from the root to this tag, resolved against a
    /// tag universe that should contain its ancestors (the full `/tags/list`
    /// payload, or a note's joined tags — Blinko joins every path segment row
    /// onto the note, so `note.tags` usually suffices).
    ///
    /// Falls back to the leaf name when ancestors are missing, so callers can
    /// always render *something* chip-shaped.
    func fullPath(in tags: [Tag]) -> String {
        let byId = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        var segments = [name]
        var visited: Set<Int> = [id]
        var current = self
        while !current.isRoot, let parent = byId[current.parent], visited.insert(parent.id).inserted {
            segments.append(parent.name)
            current = parent
        }
        return segments.reversed().joined(separator: "/")
    }
}
