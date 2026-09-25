import SwiftUI

/// The Search tab: full-text search over notes, faithful to Blinko web's
/// search — type a query, results render as the same note cards as the feed,
/// tapping one opens the shared detail screen.
///
/// State machine, in priority order:
/// 1. Empty query → prompt state (magnifying-glass placeholder).
/// 2. Searching with no results on screen → skeleton rows.
/// 3. Search failed with nothing to show → error state with Retry.
/// 4. Completed search, zero matches → "no results" state echoing the query.
/// 5. Otherwise → the results list.
///
/// Requests are debounced in `SearchViewModel`, and submitting the field
/// searches immediately. A 401 raises the same "Session expired" alert as
/// the feed and routes back to sign-in via the shared notification.
///
/// Does not own its own `NavigationStack` — `MainTabView` wraps each tab in
/// one, and `.searchable` binds to that outer stack's toolbar.
struct SearchView: View {
    @StateObject private var viewModel: SearchViewModel

    init(noteService: any NoteServiceProtocol) {
        _viewModel = StateObject(wrappedValue: SearchViewModel(noteService: noteService))
    }

    var body: some View {
        Group {
            if viewModel.trimmedQuery.isEmpty {
                promptState
            } else if viewModel.isSearching && viewModel.results.isEmpty {
                loadingState
            } else if viewModel.results.isEmpty, viewModel.showError {
                errorState
            } else if viewModel.results.isEmpty, viewModel.hasSearched {
                noResultsState
            } else if viewModel.results.isEmpty {
                // Query typed but the debounce hasn't fired yet.
                loadingState
            } else {
                resultsList
            }
        }
        .navigationTitle("Search")
        .searchable(
            text: $viewModel.query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search notes"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onSubmit(of: .search) {
            Task { await viewModel.submitSearch() }
        }
        .navigationDestination(item: $viewModel.selectedNote) { note in
            NoteDetailView(viewModel: viewModel, note: note)
        }
        .alert("Session expired", isPresented: $viewModel.requiresReauthentication) {
            Button("Sign In Again", role: .none) {
                // The coordinator observes this; it will tear down the shell.
                NotificationCenter.default.post(name: .requiresReauthentication, object: nil)
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Couldn't search notes", isPresented: $viewModel.showError) {
            Button("Retry", action: { Task { await viewModel.submitSearch() } })
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
    }

    private var promptState: some View {
        ContentUnavailableView(
            "Search Your Notes",
            systemImage: "magnifyingglass",
            description: Text("Find notes by their text. Results update as you type.")
        )
    }

    private var noResultsState: some View {
        ContentUnavailableView.search(text: viewModel.trimmedQuery)
    }

    private var errorState: some View {
        ContentUnavailableView(
            "Couldn't Search Notes",
            systemImage: "exclamationmark.triangle",
            description: Text(viewModel.errorMessage.isEmpty ? "Check your connection and try again." : viewModel.errorMessage)
        )
    }

    private var resultsList: some View {
        List {
            ForEach(viewModel.results) { note in
                NoteRowView(note: note)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.open(note) }
                    // Kicks off the next page as the last row appears.
                    .onAppear {
                        guard note.id == viewModel.results.last?.id else { return }
                        Task { await viewModel.loadMoreResults() }
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
    }

    /// Skeleton rows matching the feed's, so the list does not resize when
    /// results arrive.
    private var loadingState: some View {
        List {
            ForEach(0..<6, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(height: 16)
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(height: 12).frame(width: 200, alignment: .leading)
                }
                .padding(.vertical, 6)
                .redacted(reason: .placeholder)
            }
        }
        .listStyle(.plain)
    }
}

#if DEBUG
#Preview("Search — idle") {
    NavigationStack {
        SearchView(noteService: MockNoteService(delay: .milliseconds(0)))
    }
}

#Preview("Search — error") {
    NavigationStack {
        SearchView(noteService: MockNoteService.failing(APIError.transport("offline")))
    }
}
#endif
