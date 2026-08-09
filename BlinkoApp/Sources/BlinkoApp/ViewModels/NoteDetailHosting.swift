import Foundation

/// The contract `NoteDetailView` needs from whichever list pushed it.
///
/// Both the home feed and search results present the same detail screen with
/// the same affordances (pin, edit, delete). The detail view talks to its
/// host through this protocol instead of `HomeViewModel` directly, so each
/// list keeps ownership of how a change is merged back into its rows —
/// the feed prepends new notes, search only updates rows that still match.
@MainActor
protocol NoteDetailHosting: ObservableObject {
    /// Service handed to the editor screens spawned from the detail view.
    var noteService: any NoteServiceProtocol { get }

    /// Merges a note the editor just saved back into the host's list.
    func noteSaved(_ note: Note)

    /// Fetches the latest copy of a note (used by the detail view on open).
    func fetchNote(id: Int) async throws -> Note

    /// Pins or unpins a note, optimistically, rolling back on failure.
    func togglePin(id: Int, isPinned: Bool) async

    /// Soft-deletes the note being shown and pops back to the list on
    /// success; rethrows on failure so the detail view surfaces the error.
    func trashFromDetail(id: Int) async throws
}
