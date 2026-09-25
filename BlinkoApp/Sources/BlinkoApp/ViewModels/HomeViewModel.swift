import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject, NoteDetailHosting {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""
    /// Set when the failure was an expired/invalid token, so the app can send
    /// the user back to sign-in instead of just showing an alert. Public-set
    /// because the alert binding resets it on dismiss.
    @Published var requiresReauthentication = false

    private(set) var syncMetadata = SyncMetadata.initial

    /// Non-nil when the list is showing stale content after a failed refresh —
    /// restored from the offline cache on a cold launch, or left on screen
    /// when pull-to-refresh could not reach the server. The value is when that
    /// content was last successfully fetched, shown in the offline banner.
    /// Cleared by the next successful refresh.
    @Published private(set) var staleDataTimestamp: Date?

    var isShowingStaleData: Bool { staleDataTimestamp != nil }
    /// Active list scope. `false` (default) hides archived notes; `true`
    /// shows only the archived ones via the `isArchived` filter on the
    /// `/v1/note/list` request. Change it through ``setShowsArchived(_:)``
    /// so the list refetches with the new filter.
    @Published private(set) var showsArchived = false

    /// The note the user just tapped, pushed onto the detail route. `nil`
    /// when the list is showing. Drives a `navigationDestination` in
    /// `HomeView`, so tapping different rows swaps the detail screen without a
    /// hand-rolled `NavigationStack` path.
    @Published var selectedNote: Note?

    /// Internal (not private) so the detail/editor screens spawned from this
    /// list can reuse the same service instance.
    let noteService: any NoteServiceProtocol

    /// Optional so previews and screens that don't need offline fallback can
    /// omit it; `nil` disables caching entirely.
    private let cacheStore: (any NotesCacheStore)?

    init(noteService: any NoteServiceProtocol, cacheStore: (any NotesCacheStore)? = nil) {
        self.noteService = noteService
        self.cacheStore = cacheStore
    }

    /// Paging is suppressed while showing stale data: the cache only holds the
    /// first page, and the server that would serve page 2 is unreachable.
    var canLoadMore: Bool {
        syncMetadata.hasMore && !isLoading && !isLoadingMore && !isShowingStaleData
    }

    /// Switches the list between the active and archived scopes and reloads
    /// from page 1. No-op when the scope is unchanged, so binding re-sets
    /// don't trigger spurious refetches.
    func setShowsArchived(_ showsArchived: Bool) async {
        guard self.showsArchived != showsArchived else { return }
        self.showsArchived = showsArchived
        await loadNotes()
    }

    /// Loads the first page, replacing whatever is on screen.
    ///
    /// Offline behavior: a successful load replaces the persisted cache
    /// wholesale (which is also how server-side deletions reconcile — the
    /// fresh payload simply no longer contains them). A *retryable* failure
    /// (offline, timeout, 5xx) falls back to cached content instead of an
    /// empty error screen, flagged stale via ``staleDataTimestamp``. A
    /// non-retryable failure (401, 403, validation) never reads the cache —
    /// notably a 401 must route to sign-in, not show the previous session's
    /// notes.
    func loadNotes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        syncMetadata.reset()
        do {
            let request = NoteListRequest(page: 1, size: syncMetadata.size, isArchived: showsArchived)
            let page = try await noteService.fetchNotes(request)
            notes = page
            syncMetadata.recordLoadedPage(page, page: 1)
            staleDataTimestamp = nil
            clearError()
            await cacheStore?.save(notes: page, savedAt: Date())
        } catch {
            if isRetryable(error), let cached = await cacheStore?.load() {
                // Server unreachable but we have a previous payload: show it
                // as stale rather than erroring. Keep whatever is already on
                // screen if it's fresher than the cache file (e.g. a refresh
                // failing after a successful launch load).
                if notes.isEmpty {
                    notes = cached.notes
                }
                staleDataTimestamp = syncMetadata.lastSyncedAt ?? cached.savedAt
                clearError()
            } else if isRetryable(error), !notes.isEmpty {
                // No cache store (or empty cache) but content is on screen:
                // preserve it, banner instead of alert.
                staleDataTimestamp = syncMetadata.lastSyncedAt ?? staleDataTimestamp
                clearError()
            } else {
                present(error)
            }
        }
    }

    private func isRetryable(_ error: any Error) -> Bool {
        (error as? APIError)?.isRetryable ?? false
    }

    /// Appends the next page. No-op when a load is in flight or the list is
    /// already exhausted.
    func loadMoreNotes() async {
        guard canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = syncMetadata.nextPage
        do {
            let request = NoteListRequest(page: nextPage, size: syncMetadata.size, isArchived: showsArchived)
            let page = try await noteService.fetchNotes(request)
            notes.append(contentsOf: page)
            syncMetadata.recordLoadedPage(page, page: nextPage)
            clearError()
        } catch {
            present(error)
        }
    }

    /// Moves a note to the recycle bin, removing it from the list optimistically
    /// and restoring it if the call fails.
    func trashNote(id: Int) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let removed = notes.remove(at: index)
        do {
            try await noteService.trash(ids: [id])
        } catch {
            notes.insert(removed, at: min(index, notes.count))
            present(error)
        }
    }

    /// Tapping a row opens the note's detail route.
    func open(_ note: Note) {
        selectedNote = note
    }

    /// Returns from the detail route to the list.
    func dismissDetail() {
        selectedNote = nil
    }

    /// Compose destination: `true` routes to the note editor in create mode.
    @Published var composeRequested = false

    func composeNote() {
        composeRequested = true
    }

    /// Merges a note the editor just saved into the list.
    ///
    /// A created note is prepended (the feed is `updatedAt desc`, and the new
    /// note is by definition the freshest); an edited note is updated in
    /// place without re-sorting, mirroring how `togglePin` avoids reshuffling
    /// rows under the user's finger. Pull-to-refresh restores exact server
    /// order.
    func noteSaved(_ note: Note) {
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            notes[index] = note
        } else {
            notes.insert(note, at: 0)
        }
    }

    /// Called by the detail screen after it successfully trashed the note it
    /// was showing: drop the row and pop back to the list.
    func noteTrashed(id: Int) {
        notes.removeAll { $0.id == id }
        dismissDetail()
    }

    /// Moves a note to the recycle bin on behalf of the detail screen.
    /// Unlike `trashNote(id:)` this does not touch the list on failure and
    /// rethrows, so the detail view can keep showing the note and surface
    /// the error itself.
    func trashFromDetail(id: Int) async throws {
        try await noteService.trash(ids: [id])
        noteTrashed(id: id)
    }

    /// Fetches the latest copy of a note (used by the detail view on open).
    func fetchNote(id: Int) async throws -> Note {
        try await noteService.fetchNote(id: id)
    }

    /// Pins or unpins a note, updating the local copy optimistically and rolling
    /// back on failure.
    ///
    /// On success the list is re-sorted pinned-first (stable within each
    /// group, so server recency order is preserved), matching Blinko web
    /// where pinning floats the note to the top immediately. The re-sort
    /// happens only after the server confirms — a failed call rolls the badge
    /// back without ever moving the row.
    func togglePin(id: Int, isPinned: Bool) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isTop.toggle()
        do {
            _ = try await noteService.setTop(id: id, isTop: notes[index].isTop)
            sortPinnedFirst()
        } catch {
            notes[index].isTop = isPinned
            present(error)
        }
    }

    /// Stable pinned-first ordering: pinned notes ahead of unpinned ones,
    /// original (server) order preserved within each group. A no-op when the
    /// server already returned pinned-first pages, which `/v1/note/list` does.
    private func sortPinnedFirst() {
        notes = notes.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.isTop != rhs.element.isTop { return lhs.element.isTop }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Archives or unarchives a note. The flag is flipped optimistically, the
    /// call is dispatched, and on failure the row is restored to its previous
    /// position with the original flag. Errors surface through the same alert
    /// path as the rest of the list.
    ///
    /// When the new state is out of the current scope (the active list hides
    /// archived notes, the archived list shows only archived ones), the row is
    /// dropped from the in-memory list so the UI mirrors the web behaviour;
    /// pull-to-refresh restores the server-order if the call actually
    /// succeeded. The list is server-ordered, so the remaining rows are not
    /// re-sorted.
    func toggleArchive(id: Int) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let removed = notes[index]
        let previousIsArchived = removed.isArchived
        let newIsArchived = !previousIsArchived
        let outOfScope = (newIsArchived && !showsArchived)
            || (!newIsArchived && showsArchived)
        notes[index].isArchived = newIsArchived
        if outOfScope {
            notes.remove(at: index)
        }
        do {
            _ = try await noteService.setArchived(id: id, isArchived: newIsArchived)
        } catch {
            // Restore the in-memory state for both branches.
            if outOfScope {
                notes.insert(removed, at: min(index, notes.count))
            } else {
                notes[index].isArchived = previousIsArchived
            }
            present(error)
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        if case APIError.unauthorized = error {
            // The re-auth alert handles 401s; don't also raise the generic
            // error alert — two simultaneous alerts are unreliable.
            requiresReauthentication = true
        } else {
            showError = true
        }
    }

    private func clearError() {
        errorMessage = ""
        showError = false
    }
}
