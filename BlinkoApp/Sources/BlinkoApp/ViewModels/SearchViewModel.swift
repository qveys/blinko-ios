import Combine
import Foundation

/// Drives the Search tab: full-text search against `/v1/note/list` via
/// `NoteListRequest.searchText`, the same contract the web app uses.
///
/// Two mechanisms keep typing from flooding a self-hosted server and keep
/// the UI consistent when responses race:
///
/// - **Debounce.** Each keystroke restarts a timer; the request only fires
///   once the user pauses for `debounceInterval`. Submitting the search field
///   (or tapping Retry) skips the wait.
/// - **Generation counter.** Every accepted query bumps `generation`, and a
///   response is dropped unless its generation still matches when it lands.
///   Without this, a slow response for "sw" could overwrite the results for
///   "swift" that already arrived.
///
/// Conforms to ``NoteDetailHosting`` so tapping a result pushes the same
/// `NoteDetailView` the home feed uses — pin, edit, and delete all work and
/// write back into the results list.
@MainActor
final class SearchViewModel: ObservableObject {
    /// Live text of the search field. Setting it schedules a debounced search;
    /// clearing it resets to the idle state.
    @Published var query = "" {
        didSet {
            guard oldValue != query else { return }
            scheduleSearch()
        }
    }

    @Published private(set) var results: [Note] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLoadingMore = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""
    /// Set when the failure was an expired/invalid token, so the app can send
    /// the user back to sign-in instead of just showing an alert. Public-set
    /// because the alert binding resets it on dismiss.
    @Published var requiresReauthentication = false

    /// `true` once at least one search has completed for the current query,
    /// which is what distinguishes "no results" from "hasn't searched yet".
    @Published private(set) var hasSearched = false

    /// The result the user tapped, pushed onto the detail route. Mirrors
    /// `HomeViewModel.selectedNote`.
    @Published var selectedNote: Note?

    private(set) var syncMetadata = SyncMetadata.initial

    /// Internal (not private) so the detail/editor screens spawned from the
    /// results list can reuse the same service instance.
    let noteService: any NoteServiceProtocol

    private let debounceInterval: Duration
    private var debounceTask: Task<Void, Never>?
    /// Bumped whenever the accepted query changes; in-flight responses from
    /// older generations are discarded when they land.
    private var generation = 0
    /// The trimmed query the current results belong to. Pagination keeps
    /// requesting this text even if the field has since changed.
    private var activeQuery = ""

    init(
        noteService: any NoteServiceProtocol,
        debounceInterval: Duration = .milliseconds(300)
    ) {
        self.noteService = noteService
        self.debounceInterval = debounceInterval
    }

    var canLoadMore: Bool { syncMetadata.hasMore && !isSearching && !isLoadingMore }

    /// Trimmed query text; searches never fire for whitespace-only input.
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the search immediately, skipping the debounce. Wired to the
    /// search field's submit action and the error state's Retry button.
    func submitSearch() async {
        debounceTask?.cancel()
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            resetToIdle()
            return
        }
        await search(for: trimmed)
    }

    /// Fetches the next page of the current results. No-op while another
    /// load is running or when the last page came back short.
    func loadMoreResults() async {
        guard canLoadMore, hasSearched else { return }
        let requestGeneration = generation
        let pageNumber = syncMetadata.nextPage
        isLoadingMore = true
        do {
            let request = NoteListRequest(
                page: pageNumber,
                size: syncMetadata.size,
                searchText: activeQuery
            )
            let page = try await noteService.fetchNotes(request)
            // A newer search started while this page was in flight; its
            // reset already owns the list state.
            guard requestGeneration == generation else { return }
            isLoadingMore = false
            results.append(contentsOf: page)
            syncMetadata.recordLoadedPage(page, page: pageNumber)
        } catch {
            guard requestGeneration == generation else { return }
            isLoadingMore = false
            present(error)
        }
    }

    // MARK: - Navigation

    func open(_ note: Note) {
        selectedNote = note
    }

    /// Returns from the detail route to the results list.
    func dismissDetail() {
        selectedNote = nil
    }

    // MARK: - Debounce plumbing

    /// Restarts the debounce timer for the current query, or resets to idle
    /// when the field was cleared. Cancelling the previous task is what
    /// coalesces a burst of keystrokes into one request.
    private func scheduleSearch() {
        debounceTask?.cancel()
        let trimmed = trimmedQuery
        guard !trimmed.isEmpty else {
            resetToIdle()
            return
        }
        debounceTask = Task { [weak self, debounceInterval] in
            try? await Task.sleep(for: debounceInterval)
            guard !Task.isCancelled else { return }
            await self?.search(for: trimmed)
        }
    }

    /// Loads the first page for `trimmed`, replacing whatever is on screen.
    private func search(for trimmed: String) async {
        generation += 1
        let requestGeneration = generation
        activeQuery = trimmed
        isSearching = true
        isLoadingMore = false
        syncMetadata.reset()
        do {
            let request = NoteListRequest(
                page: 1,
                size: syncMetadata.size,
                searchText: trimmed
            )
            let page = try await noteService.fetchNotes(request)
            // Drop stale responses: a newer query has been accepted since
            // this request left, and its response owns the UI.
            guard requestGeneration == generation else { return }
            results = page
            syncMetadata.recordLoadedPage(page, page: 1)
            hasSearched = true
            isSearching = false
            clearError()
        } catch {
            guard requestGeneration == generation else { return }
            isSearching = false
            present(error)
        }
    }

    /// Cancels any in-flight work and clears results — the empty-query state.
    private func resetToIdle() {
        generation += 1
        activeQuery = ""
        results = []
        hasSearched = false
        isSearching = false
        isLoadingMore = false
        syncMetadata = .initial
        clearError()
    }

    // MARK: - Errors

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

// MARK: - NoteDetailHosting

extension SearchViewModel: NoteDetailHosting {
    /// Merges a note the editor just saved into the results in place. Search
    /// results are query-ordered by the server, so no re-sorting — and unlike
    /// the home feed, an unknown note is not prepended: a note edited from
    /// search may simply no longer match the query, which refreshing settles.
    func noteSaved(_ note: Note) {
        guard let index = results.firstIndex(where: { $0.id == note.id }) else { return }
        results[index] = note
    }

    /// Fetches the latest copy of a note (used by the detail view on open).
    func fetchNote(id: Int) async throws -> Note {
        try await noteService.fetchNote(id: id)
    }

    /// Pins or unpins a note, updating the local copy optimistically and
    /// rolling back on failure. Mirrors `HomeViewModel.togglePin`.
    func togglePin(id: Int, isPinned: Bool) async {
        guard let index = results.firstIndex(where: { $0.id == id }) else { return }
        results[index].isTop.toggle()
        do {
            _ = try await noteService.setTop(id: id, isTop: results[index].isTop)
        } catch {
            results[index].isTop = isPinned
            present(error)
        }
    }

    /// Moves a note to the recycle bin on behalf of the detail screen,
    /// dropping the result row and popping back on success. Rethrows so the
    /// detail view can surface the failure itself.
    func trashFromDetail(id: Int) async throws {
        try await noteService.trash(ids: [id])
        results.removeAll { $0.id == id }
        dismissDetail()
    }
}
