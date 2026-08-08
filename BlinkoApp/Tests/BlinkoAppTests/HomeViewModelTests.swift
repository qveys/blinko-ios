import XCTest
@testable import BlinkoApp

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testLoadNotesPopulatesNotes() async {
        let service = MockNoteService(notes: [
            Note(id: 1, content: "Hello Blinko", type: .blinko, isTop: false,
                 createdAt: .now, updatedAt: .now)
        ])
        let vm = HomeViewModel(noteService: service)

        await vm.loadNotes()

        XCTAssertEqual(vm.notes.count, 1)
        XCTAssertFalse(vm.showError)
    }

    func testLoadNotesShowsErrorOnFailure() async {
        let service = MockNoteService(error: URLError(.notConnectedToInternet))
        let vm = HomeViewModel(noteService: service)

        await vm.loadNotes()

        XCTAssertTrue(vm.notes.isEmpty)
        XCTAssertTrue(vm.showError)
    }
}

private final class MockNoteService: NoteServiceProtocol {
    private let notes: [Note]
    private let error: Error?

    init(notes: [Note] = [], error: Error? = nil) {
        self.notes = notes
        self.error = error
    }

    func fetchNotes() async throws -> [Note] {
        if let error { throw error }
        return notes
    }

    func createNote(content: String, type: Note.NoteType) async throws -> Note {
        if let error { throw error }
        return Note(id: 2, content: content, type: type, isTop: false, createdAt: .now, updatedAt: .now)
    }
}
