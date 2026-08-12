import SwiftUI

/// The authenticated home surface: a server-backed notes list with empty,
/// loading, and error states, pull-to-refresh, and navigation to a note's
/// detail route on tap.
///
/// State machine, in priority order:
/// 1. First load → skeleton rows (not a centered spinner — the web list does
///    not jump height once content arrives).
/// 2. Load failed → error state with Retry.
/// 3. No notes → empty state.
/// 4. Otherwise → the list.
///
/// A 401 failure sets `requiresReauthentication`; the alert offers a
/// "Sign In Again" button that the coordinator consumes via the binding.
///
/// Does not own its own `NavigationStack`: `MainTabView` wraps each tab
/// destination in one, and nesting a second stack would double the nav bar
/// and leave `.navigationDestination` bound to the inner stack instead of
/// the tab's. The detail and compose routes bind to the outer stack.
struct HomeView: View {
    @StateObject private var viewModel: HomeViewModel

    init(
        noteService: any NoteServiceProtocol,
        attachmentService: any AttachmentServiceProtocol = MockAttachmentService()
    ) {
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(
                noteService: noteService,
                attachmentService: attachmentService
            )
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.notes.isEmpty {
                loadingState
            } else if viewModel.notes.isEmpty, viewModel.showError {
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
                .accessibilityLabel("New note")
            }
        }
        .navigationDestination(item: $viewModel.selectedNote) { note in
            NoteDetailView(viewModel: viewModel, note: note)
        }
        .navigationDestination(isPresented: $viewModel.composeRequested) {
            NoteEditorView(
                noteService: viewModel.noteService,
                attachmentService: viewModel.attachmentService,
                onSaved: viewModel.noteSaved
            )
        }
        .task { await viewModel.loadNotes() }
        .alert("Session expired", isPresented: $viewModel.requiresReauthentication) {
            Button("Sign In Again", role: .none) {
                // The coordinator observes this; it will tear down the shell.
                NotificationCenter.default.post(name: .requiresReauthentication, object: nil)
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .alert("Couldn't load notes", isPresented: $viewModel.showError) {
            Button("Retry", action: { Task { await viewModel.loadNotes() } })
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
            description: Text(viewModel.errorMessage.isEmpty ? "Check your connection and try again." : viewModel.errorMessage)
        )
    }

    private var notesList: some View {
        List {
            ForEach(viewModel.notes) { note in
                NoteRowView(note: note)
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.open(note) }
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

    /// Skeleton rows that match the real row height, so the list does not
    /// resize when content arrives.
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

extension Notification.Name {
    /// Posted when a 401 should route the user back to sign-in. Observed by
    /// the app coordinator, which owns the auth shell.
    static let requiresReauthentication = Notification.Name("requiresReauthentication")
}

#if DEBUG
#Preview("Home — content") {
    NavigationStack {
        HomeView(noteService: MockNoteService(delay: .milliseconds(0)))
    }
}

#Preview("Home — error") {
    NavigationStack {
        HomeView(noteService: MockNoteService.failing(APIError.transport("offline")))
    }
}
#endif
