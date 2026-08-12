import SwiftUI

/// The note editor, used for both create and edit.
///
/// Blinko has no separate title column — the first line of the markdown body
/// *is* the title (see `Note.displayTitle`), so the editor is a single
/// markdown text area rather than title + body fields. That matches the web
/// composer's basic expectations: plain markdown source in, rendering on the
/// read screen.
///
/// Failure UX (the BLI-20 acceptance criterion): a failed save keeps the
/// draft in the editor and offers Retry — nothing the user typed is lost.
/// Cancelling with unsaved text asks before discarding.
///
/// Tag typeahead (BLI-39): typing `#` surfaces matching existing tags in a
/// bar above the keyboard; tapping one splices `#tag ` into the content at
/// the token. The editor is a `UITextView` wrapper because the typeahead is
/// caret-driven and `TextEditor` cannot report the caret.
struct NoteEditorView: View {
    @StateObject private var viewModel: NoteEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDiscard = false
    @State private var editorFocused = false
    /// One-shot caret move request consumed by ``MarkdownTextView`` after a
    /// suggestion is accepted.
    @State private var caretRequest: Int?

    /// - Parameters:
    ///   - tagService: source for hashtag typeahead suggestions; `nil`
    ///     disables the typeahead (previews/legacy call sites).
    ///   - note: the note to edit, or `nil` to create a new one.
    ///   - onSaved: receives the server's copy after a successful save.
    init(
        noteService: any NoteServiceProtocol,
        tagService: (any TagServiceProtocol)? = nil,
        note: Note? = nil,
        onSaved: @escaping (Note) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: NoteEditorViewModel(
                noteService: noteService,
                tagService: tagService,
                note: note,
                onSaved: onSaved
            )
        )
    }

    var body: some View {
        MarkdownTextView(
            text: $viewModel.content,
            caretRequest: $caretRequest,
            isFocused: $editorFocused,
            onCaretChange: { viewModel.caretMoved(toUTF16Offset: $0) }
        )
        .overlay(alignment: .topLeading) {
            if viewModel.content.isEmpty {
                // UITextView has no placeholder; fake one that doesn't
                // intercept taps.
                Text("Write in markdown — the first line becomes the title.")
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 17)
                    .padding(.top, 8)
                    .allowsHitTesting(false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showSuggestionBar {
                TagSuggestionBar(
                    suggestions: viewModel.tagSuggestions,
                    showNoMatch: viewModel.showNoTagMatch,
                    isLoading: viewModel.isLoadingTags,
                    onSelect: acceptSuggestion
                )
            }
        }
            .navigationTitle(isEditing ? "Edit Note" : "New Note")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .disabled(viewModel.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await saveAndDismiss() }
                        }
                        .disabled(!viewModel.canSave)
                        .accessibilityLabel("Save note")
                    }
                }
            }
            .confirmationDialog(
                "Discard this draft?",
                isPresented: $confirmDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive, action: dismiss.callAsFunction)
                Button("Keep Editing", role: .cancel) {}
            }
            .alert("Couldn't save note", isPresented: $viewModel.showError) {
                Button("Retry") { Task { await saveAndDismiss() } }
                Button("OK", role: .cancel) {}
            } message: {
                // The draft is still in the editor — say so, or a transient
                // network error reads like data loss.
                Text("\(viewModel.errorMessage)\n\nYour draft is preserved.")
            }
            .alert("Session expired", isPresented: $viewModel.requiresReauthentication) {
                Button("Sign In Again") {
                    NotificationCenter.default.post(name: .requiresReauthentication, object: nil)
                }
                Button("Dismiss", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage)
            }
            .onAppear { editorFocused = true }
    }

    private var isEditing: Bool {
        if case .edit = viewModel.mode { return true }
        return false
    }

    /// The bar occupies space only when it has something to say: matches,
    /// the `No tag found` row, or the initial-load spinner.
    private var showSuggestionBar: Bool {
        !viewModel.tagSuggestions.isEmpty || viewModel.showNoTagMatch || viewModel.isLoadingTags
    }

    private func acceptSuggestion(_ suggestion: TagTypeahead.Suggestion) {
        if let caret = viewModel.acceptSuggestion(suggestion) {
            // Move the caret past the inserted `#tag ` and keep the keyboard
            // up — focus stays in the editor per the spec.
            caretRequest = caret
            editorFocused = true
        }
    }

    private func cancel() {
        if viewModel.hasUnsavedChanges {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func saveAndDismiss() async {
        if await viewModel.save() {
            dismiss()
        }
    }
}

#if DEBUG
#Preview("Create") {
    NavigationStack {
        NoteEditorView(noteService: MockNoteService(), tagService: MockTagService())
    }
}

#Preview("Edit") {
    let base = Date(timeIntervalSince1970: 1_725_000_000)
    let note = Note(
        id: 1,
        content: "# Quarter plan\n\nShip the notes list before the freeze.",
        createdAt: base,
        updatedAt: base
    )
    return NavigationStack {
        NoteEditorView(noteService: MockNoteService(notes: [note]), tagService: MockTagService(), note: note)
    }
}
#endif
