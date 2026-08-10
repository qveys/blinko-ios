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

    init(noteService: any NoteServiceProtocol) {
        _viewModel = StateObject(wrappedValue: HomeViewModel(noteService: noteService))
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
        .navigationTitle(viewModel.showsArchived ? "Archived" : "Blinko")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.composeNote) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New note")
            }
            ToolbarItem(placement: .secondaryAction) {
                // A menu rather than a bare toggle so future scopes (recycle
                // bin, shared) have an obvious place to land.
                Menu {
                    Toggle(
                        "Show Archived",
                        systemImage: "archivebox",
                        isOn: Binding(
                            get: { viewModel.showsArchived },
                            set: { newValue in Task { await viewModel.setShowsArchived(newValue) } }
                        )
                    )
                } label: {
                    Image(systemName: viewModel.showsArchived
                        ? "line.3.horizontal.decrease.circle.fill"
                        : "line.3.horizontal.decrease.circle")
                }
                .accessibilityLabel("Filter notes")
            }
        }
        .navigationDestination(item: $viewModel.selectedNote) { note in
            NoteDetailView(viewModel: viewModel, note: note)
        }
        .navigationDestination(isPresented: $viewModel.composeRequested) {
            NoteEditorView(
                noteService: viewModel.noteService,
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

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.showsArchived {
            ContentUnavailableView(
                "No Archived Notes",
                systemImage: "archivebox",
                description: Text("Notes you archive will show up here.")
            )
        } else {
            ContentUnavailableView(
                "No Notes",
                systemImage: "note.text",
                description: Text("Tap the compose button to add your first note.")
            )
        }
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
                    // Leading swipe mirrors Mail's pin-like affordance;
                    // trailing carries the destructive/archival pair, matching
                    // the actions Blinko web exposes on each card's menu.
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        pinButton(for: note)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        trashButton(for: note)
                        archiveButton(for: note)
                    }
                    .contextMenu {
                        pinButton(for: note)
                        archiveButton(for: note)
                        Divider()
                        trashButton(for: note)
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

    /// Pin/unpin — label and icon flip with the note's current state.
    private func pinButton(for note: Note) -> some View {
        Button {
            Task { await viewModel.togglePin(id: note.id, isPinned: note.isPinned) }
        } label: {
            Label(
                note.isPinned ? "Unpin" : "Pin",
                systemImage: note.isPinned ? "pin.slash" : "pin"
            )
        }
        .tint(.orange)
    }

    /// Archive/unarchive — the row leaves the current scope on success.
    private func archiveButton(for note: Note) -> some View {
        Button {
            Task { await viewModel.toggleArchive(id: note.id) }
        } label: {
            Label(
                note.isArchived ? "Unarchive" : "Archive",
                systemImage: note.isArchived ? "tray.and.arrow.up" : "archivebox"
            )
        }
        .tint(.indigo)
    }

    /// Soft-delete into the recycle bin — reuses the existing trash flow.
    private func trashButton(for note: Note) -> some View {
        Button(role: .destructive) {
            Task { await viewModel.trashNote(id: note.id) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
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
