import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.notes.isEmpty {
                    emptyState
                } else {
                    notesList
                }
            }
            .navigationTitle("Blinko")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: viewModel.composeNote) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
        .task { await viewModel.loadNotes() }
        .alert("Error", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Notes",
            systemImage: "note.text",
            description: Text("Tap the compose button to add your first note.")
        )
    }

    private var notesList: some View {
        List(viewModel.notes) { note in
            NoteRowView(note: note)
        }
        .listStyle(.plain)
    }
}
