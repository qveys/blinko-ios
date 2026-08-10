import SwiftUI

/// Read view for a single note: markdown-rendered content, tags, metadata,
/// and the note-level actions (pin, edit, delete).
///
/// Editing pushes ``NoteEditorView`` pre-filled with the note's markdown;
/// a successful save updates both this screen and the owning list through
/// ``HomeViewModel/noteSaved(_:)``. Delete asks for confirmation first
/// (destructive), soft-deletes into the recycle bin — the same semantics as
/// Blinko web's delete — and pops back to the list only when the server call
/// succeeds.
struct NoteDetailView: View {
    @ObservedObject var viewModel: HomeViewModel
    let note: Note

    @State private var detail: Note
    @State private var loadError: String?
    @State private var showError = false
    @State private var isReloading = false
    @State private var editRequested = false
    @State private var confirmDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @State private var showDeleteError = false

    init(viewModel: HomeViewModel, note: Note) {
        self.viewModel = viewModel
        self.note = note
        self._detail = State(initialValue: note)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isReloading {
                    loadingShimmer
                } else {
                    contentView
                }
            }
            .padding()
        }
        .navigationTitle(note.displayTitle.isEmpty ? "Note" : note.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                actionsMenu
            }
        }
        .navigationDestination(isPresented: $editRequested) {
            NoteEditorView(
                noteService: viewModel.noteService,
                note: detail,
                onSaved: { saved in
                    detail = saved
                    viewModel.noteSaved(saved)
                }
            )
        }
        .confirmationDialog(
            "Delete this note?",
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Note", role: .destructive) {
                Task { await deleteNote() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The note moves to the recycle bin.")
        }
        .alert("Couldn't delete note", isPresented: $showDeleteError) {
            Button("Retry") { Task { await deleteNote() } }
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn't load note", isPresented: $showError) {
            Button("OK", role: .cancel) { loadError = nil }
        } message: {
            Text(loadError ?? "")
        }
        .task { await refresh() }
    }

    @ViewBuilder
    private var contentView: some View {
        if detail.isEmpty {
            Text("This note is empty.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            MarkdownContentView(markdown: detail.content)
        }

        if !detail.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.headline)
                NoteTagChipRow(tags: detail.tags, onTap: { tag in
                    // Chip tap-through: pop back to the list with the tag
                    // applied as its filter (BLI-29).
                    Task {
                        viewModel.dismissDetail()
                        await viewModel.applyTagFilter(tag, in: detail.tags)
                    }
                })
            }
        }

        Divider()
        metadataSection
    }

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow(label: "Created", date: detail.createdAt)
            metadataRow(label: "Updated", date: detail.updatedAt)
            if detail.isArchived {
                Label("Archived", systemImage: "archivebox")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metadataRow(label: String, date: Date) -> some View {
        HStack {
            Text(label)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(date.formatted(date: .abbreviated, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Edit is the primary affordance, so it sits directly in the bar; pin
    /// and delete live behind the ellipsis. Delete is `.destructive` and
    /// still confirms before calling the server.
    private var actionsMenu: some View {
        HStack(spacing: 4) {
            Button {
                editRequested = true
            } label: {
                Label("Edit", systemImage: "square.and.pencil")
            }
            .disabled(isDeleting)
            .accessibilityLabel("Edit note")

            Menu {
                Button {
                    Task { await viewModel.togglePin(id: detail.id, isPinned: detail.isPinned) }
                    detail.isTop.toggle()
                } label: {
                    Label(
                        detail.isPinned ? "Unpin" : "Pin",
                        systemImage: detail.isPinned ? "pin.slash.fill" : "pin"
                    )
                }

                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                if isDeleting {
                    ProgressView()
                } else {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .disabled(isDeleting)
            .accessibilityLabel("Note actions")
        }
    }

    private var loadingShimmer: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(height: 18)
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(height: 18)
            RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15)).frame(width: 140, height: 14)
        }
        .redacted(reason: .placeholder)
    }

    /// Re-fetches the note so the detail view shows the latest server state,
    /// falling back to the passed-in note on failure.
    private func refresh() async {
        isReloading = true
        defer { isReloading = false }
        do {
            detail = try await viewModel.fetchNote(id: note.id)
        } catch {
            // A stale row is better than a blank screen; surface the failure
            // without throwing the user out of the screen they just opened.
            loadError = error.localizedDescription
            showError = true
        }
    }

    /// Soft-deletes the note. On success the view model pops this screen and
    /// removes the row; on failure the note stays put and the error alert
    /// offers Retry — the user never loses the note to a half-failed delete.
    private func deleteNote() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await viewModel.trashFromDetail(id: detail.id)
        } catch {
            deleteError = error.localizedDescription
            showDeleteError = true
        }
    }
}

#if DEBUG
#Preview("Note detail") {
    let base = Date(timeIntervalSince1970: 1_725_000_000)
    let note = Note(
        id: 1,
        content: "# Quarter plan\n\nShip the notes list before the freeze.\n\n- Editor\n- Markdown\n\nDetails follow here.",
        type: .note,
        isTop: true,
        createdAt: base,
        updatedAt: base,
        tagRelations: [
            TagRelation(noteId: 1, tagId: 7, tag: Tag(id: 7, name: "projects", parent: 3, createdAt: base, updatedAt: base))
        ]
    )
    return NavigationStack {
        NoteDetailView(viewModel: HomeViewModel(noteService: MockNoteService(notes: [note])), note: note)
    }
}
#endif
