import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""
    /// Set when the failure was an expired/invalid token, so the app can send
    /// the user back to sign-in instead of just showing an alert.
    @Published private(set) var requiresReauthentication = false

    private(set) var syncMetadata = SyncMetadata.initial

    private let noteService: any NoteServiceProtocol

    init(noteService: any NoteServiceProtocol) {
        self.noteService = noteService
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

    func composeNote() {
        // navigation handled by coordinator in a future iteration
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        showError = true
        if case APIError.unauthorized = error {
            requiresReauthentication = true
        }
    }

    private func clearError() {
        errorMessage = ""
        showError = false
    }
}
