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
    @StateObject private var tagFilterViewModel: TagFilterViewModel

    /// - Parameters:
    ///   - tagService: powers both the filter sheet's tag tree and the
    ///     editor's hashtag typeahead, so it is threaded onto the view model
    ///     as well as the filter view model.
    ///   - tagsCacheStore: offline fallback for the filter sheet; `nil`
    ///     disables caching (previews, tests).
    init(
        noteService: any NoteServiceProtocol,
        tagService: any TagServiceProtocol,
        tagsCacheStore: (any TagsCacheStore)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: HomeViewModel(noteService: noteService, tagService: tagService)
        )
        _tagFilterViewModel = StateObject(
            wrappedValue: TagFilterViewModel(tagService: tagService, cacheStore: tagsCacheStore)
        )
    }

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.notes.isEmpty {
                loadingState
            } else if viewModel.notes.isEmpty, viewModel.showError {
                errorState
            } else if viewModel.notes.isEmpty, viewModel.activeTagFilter != nil {
                filteredEmptyState
            } else if viewModel.notes.isEmpty {
                emptyState
            } else {
                notesList
            }
        }
        .navigationTitle("Blinko")
        .toolbar {
            // Filter first so it sits left of compose, mirroring web's
            // sidebar-then-content order.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isTagFilterSheetPresented = true
                } label: {
                    Image(systemName: viewModel.activeTagFilter == nil
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityLabel(
                    viewModel.activeTagFilter.map { "Filter by tag, active: \($0.fullPath)" }
                        ?? "Filter by tag"
                )
            }
            ToolbarItem(placement: .primaryAction) {
                Button(action: viewModel.composeNote) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New note")
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let filter = viewModel.activeTagFilter {
                activeFilterBar(filter)
            }
        }
        // Light selection haptic when a filter is applied or cleared (BLI-29).
        .sensoryFeedback(.selection, trigger: viewModel.activeTagFilter)
        .sheet(isPresented: $viewModel.isTagFilterSheetPresented) {
            TagFilterSheet(
                viewModel: tagFilterViewModel,
                activeFilter: viewModel.activeTagFilter
            ) { selection in
                Task {
                    if let selection {
                        await viewModel.applyTagFilter(selection)
                    } else {
                        viewModel.isTagFilterSheetPresented = false
                        await viewModel.clearTagFilter()
                    }
                }
            }
        }
        .navigationDestination(item: $viewModel.selectedNote) { note in
            NoteDetailView(viewModel: viewModel, note: note)
        }
        .navigationDestination(isPresented: $viewModel.composeRequested) {
            NoteEditorView(
                noteService: viewModel.noteService,
                tagService: viewModel.tagService,
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

    /// The removable chip showing the active tag filter, pinned above the
    /// list: `#tag/path` plus a clear affordance.
    private func activeFilterBar(_ filter: ActiveTagFilter) -> some View {
        HStack {
            Button {
                Task { await viewModel.clearTagFilter() }
            } label: {
                HStack(spacing: 6) {
                    Text("#\(filter.fullPath)")
                        .font(.footnote.weight(.medium))
                        .lineLimit(1)
                    Image(systemName: "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule(style: .continuous).fill(Color.accentColor.opacity(0.12)))
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 0.5)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filtered by tag \(filter.fullPath), clear filter")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// Empty state specific to a tag filter with no matching notes, with the
    /// clear-filter escape hatch front and center.
    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label("No notes with #\(viewModel.activeTagFilter?.fullPath ?? "")", systemImage: "number")
        } description: {
            Text("Clear the tag filter or add this hashtag to a note.")
        } actions: {
            Button("Clear filter") {
                Task { await viewModel.clearTagFilter() }
            }
            .buttonStyle(.borderedProminent)
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
                NoteRowView(note: note, onTagTap: { tag in
                    // Chip tap-through: apply the tag as the list filter.
                    Task { await viewModel.applyTagFilter(tag, in: note.tags) }
                })
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
        HomeView(
            noteService: MockNoteService(delay: .milliseconds(0)),
            tagService: MockTagService()
        )
    }
}

#Preview("Home — error") {
    NavigationStack {
        HomeView(
            noteService: MockNoteService.failing(APIError.transport("offline")),
            tagService: MockTagService()
        )
    }
}
#endif
