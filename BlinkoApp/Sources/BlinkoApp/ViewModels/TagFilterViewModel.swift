import Combine
import Foundation

/// Drives the tag filter sheet: loads the flat tag list, assembles the tree,
/// and tracks which parent rows are expanded.
///
/// Offline behavior mirrors BLI-33's notes read cache: a successful fetch
/// replaces the persisted cache wholesale; a *retryable* failure (offline,
/// timeout, 5xx) falls back to the cached payload instead of an error state.
/// A non-retryable failure (401, validation) shows the error — stale tags
/// must not mask an expired session.
@MainActor
final class TagFilterViewModel: ObservableObject {
    @Published private(set) var tree: [TagTreeNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadFailed = false
    @Published private(set) var errorMessage = ""
    /// Parent rows the user has expanded. Roots start collapsed, matching
    /// the web sidebar's initial state.
    @Published private(set) var expandedTagIds: Set<Int> = []
    /// False until the first load settles, so the sheet shows skeletons on
    /// first open instead of flashing the "No tags yet" empty state.
    @Published private(set) var hasLoaded = false

    private let tagService: any TagServiceProtocol
    private let cacheStore: (any TagsCacheStore)?

    /// - Parameters:
    ///   - tagService: source of truth for the tag list.
    ///   - cacheStore: optional offline fallback; `nil` disables caching
    ///     (previews, tests that don't care).
    init(tagService: any TagServiceProtocol, cacheStore: (any TagsCacheStore)? = nil) {
        self.tagService = tagService
        self.cacheStore = cacheStore
    }

    var isEmpty: Bool { tree.isEmpty && hasLoaded && !isLoading && !loadFailed }

    /// Loads tags and rebuilds the tree. Safe to call repeatedly (sheet
    /// re-opens, Retry button).
    func loadTags() async {
        guard !isLoading else { return }
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let tags = try await tagService.fetchTags()
            tree = TagTreeBuilder.buildTree(from: tags)
            loadFailed = false
            errorMessage = ""
            await cacheStore?.save(tags: tags, savedAt: Date())
        } catch {
            if isRetryable(error), let cached = await cacheStore?.load() {
                tree = TagTreeBuilder.buildTree(from: cached.tags)
                loadFailed = false
                errorMessage = ""
            } else {
                loadFailed = true
                errorMessage = error.localizedDescription
            }
        }
    }

    func isExpanded(_ node: TagTreeNode) -> Bool {
        expandedTagIds.contains(node.id)
    }

    func toggleExpanded(_ node: TagTreeNode) {
        if !expandedTagIds.insert(node.id).inserted {
            expandedTagIds.remove(node.id)
        }
    }

    /// The rows to render, in display order: depth-first through expanded
    /// nodes only, with each row's indentation depth.
    var visibleRows: [(node: TagTreeNode, depth: Int)] {
        var rows: [(TagTreeNode, Int)] = []
        func walk(_ nodes: [TagTreeNode], depth: Int) {
            for node in nodes {
                rows.append((node, depth))
                if node.hasChildren, isExpanded(node) {
                    walk(node.children, depth: depth + 1)
                }
            }
        }
        walk(tree, depth: 0)
        return rows
    }

    private func isRetryable(_ error: any Error) -> Bool {
        (error as? APIError)?.isRetryable ?? false
    }
}
