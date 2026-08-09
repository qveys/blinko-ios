import SwiftUI

/// Read view for a single note: full content, tags, metadata, and the
/// non-destructive affordances available from a list tap.
///
/// Editing (inline markdown edit + save) is BLI-20's scope; this view is
/// intentionally read-only but structured — content is rendered in a
/// `ScrollView` with a toolbar that BLI-20 can swap for an edit button. The
/// destructive actions (`trash`, `pin`) are wired through the owning
/// ``HomeViewModel`` so the list stays in sync when the user comes back.
struct NoteDetailView: View {
    @ObservedObject var viewModel: HomeViewModel
    let note: Note

    @State private var detail: Note
    @State private var loadError: String?
    @State private var showError = false
    @State private var isReloading = false

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
                pinToggle
            }
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
            Text(detail.content)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !detail.tags.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tags")
                    .font(.headline)
                NoteTagChipRow(tags: detail.tags)
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

    private var pinToggle: some View {
        Button {
            Task { await viewModel.togglePin(id: detail.id, isPinned: detail.isPinned) }
            detail.isTop.toggle()
        } label: {
            Label(
                detail.isPinned ? "Unpin" : "Pin",
                systemImage: detail.isPinned ? "pin.slash.fill" : "pin"
            )
        }
        .accessibilityLabel(detail.isPinned ? "Unpin note" : "Pin note")
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
}

#if DEBUG
#Preview("Note detail") {
    let base = Date(timeIntervalSince1970: 1_725_000_000)
    let note = Note(
        id: 1,
        content: "# Quarter plan\n\nShip the notes list before the freeze.\n\nDetails follow here.",
        type: .note,
        isTop: true,
        createdAt: base,
        updatedAt: base,
        tagRelations: [
            TagRelation(noteId: 1, tagId: 7, tag: Tag(id: 7, name: "projects", parent: 3, createdAt: base, updatedAt: base))
        ]
    )
    return NavigationStack {
        NoteDetailView(viewModel: HomeViewModel(noteService: MockNoteService()), note: note)
    }
}
#endif
