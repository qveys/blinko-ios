import Combine
import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
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

    /// The note the user just tapped, pushed onto the detail route. `nil`
    /// when the list is showing. Drives a `navigationDestination` in
    /// `HomeView`, so tapping different rows swaps the detail screen without a
    /// hand-rolled `NavigationStack` path.
    @Published var selectedNote: Note?

    /// Internal (not private) so the detail/editor screens spawned from this
    /// list can reuse the same service instance.
    let noteService: any NoteServiceProtocol
    /// Handed to editor screens for hashtag typeahead suggestions (BLI-39).
    /// Optional so tests and previews that don't exercise tags need no mock.
    let tagService: (any TagServiceProtocol)?

    init(noteService: any NoteServiceProtocol, tagService: (any TagServiceProtocol)? = nil) {
        self.noteService = noteService
        self.tagService = tagService
    }

    var canLoadMore: Bool { syncMetadata.hasMore && !isLoading && !isLoadingMore }

    /// Loads the first page, replacing whatever is on screen.
    func loadNotes() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        syncMetadata.reset()
        do {
            let request = NoteListRequest(page: 1, size: syncMetadata.size)
            let page = try await noteService.fetchNotes(request)
            notes = page
            syncMetadata.recordLoadedPage(page, page: 1)
            clearError()
        } catch {
            present(error)
        }
    }

    /// Appends the next page. No-op when a load is in flight or the list is
    /// already exhausted.
    func loadMoreNotes() async {
        guard canLoadMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = syncMetadata.nextPage
        do {
            let request = NoteListRequest(page: nextPage, size: syncMetadata.size)
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
    /// back on failure. The list itself is server-ordered, so the row is not
    /// re-sorted — the pinned badge just flips.
    func togglePin(id: Int, isPinned: Bool) async {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isTop.toggle()
        do {
            _ = try await noteService.setTop(id: id, isTop: notes[index].isTop)
        } catch {
            notes[index].isTop = isPinned
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
