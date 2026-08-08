import Foundation

@MainActor
final class HomeViewModel: ObservableObject {
    @Published private(set) var notes: [Note] = []
    @Published private(set) var isLoading = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""

    private let noteService: NoteServiceProtocol

    init(noteService: NoteServiceProtocol = NoteService()) {
        self.noteService = noteService
    }

    func loadNotes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            notes = try await noteService.fetchNotes()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    func composeNote() {
        // navigation handled by coordinator in a future iteration
    }
}
