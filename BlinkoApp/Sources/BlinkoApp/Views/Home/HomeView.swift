import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel

    init(noteService: any NoteServiceProtocol) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(noteService: noteService))
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView()
                } else if viewModel.notes.isEmpty, !viewModel.errorMessage.isEmpty {
                    errorState
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

    private var errorState: some View {
        ContentUnavailableView(
            "Couldn't Load Notes",
            systemImage: "exclamationmark.triangle",
            description: Text(viewModel.errorMessage)
        )
    }

    private var notesList: some View {
        List {
            ForEach(viewModel.notes) { note in
                NoteRowView(note: note)
                    // Kicks off the next page as the last row appears.
                    .onAppear {
                        guard note.id == viewModel.notes.last?.id else { return }
                        Task { await viewModel.loadMoreNotes() }
                    }
            }
            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await viewModel.loadNotes() }
    }
}
