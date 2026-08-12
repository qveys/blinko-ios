import Combine
import Foundation

/// Drives the note editor for both create (`note == nil`) and edit flows.
///
/// Failure handling is deliberately draft-preserving: a failed save leaves
/// `content` untouched and raises a recoverable alert, so a network drop
/// never eats the user's text. Full offline sync is out of scope for BLI-20 —
/// the contract here is only "the draft survives and Retry works".
@MainActor
final class NoteEditorViewModel: ObservableObject {
    enum Mode: Equatable {
        case create
        /// Editing an existing note; holds the id being updated.
        case edit(id: Int)
    }

    @Published var content: String
    @Published private(set) var isSaving = false
    @Published var showError = false
    @Published private(set) var errorMessage = ""
    /// Mirrors `HomeViewModel`: a 401 routes to re-auth instead of the
    /// generic error alert.
    @Published var requiresReauthentication = false

    // MARK: Tag typeahead (BLI-39)

    /// Suggestions for the hashtag token at the caret; empty when no token is
    /// active. The view renders these as the suggestion bar.
    @Published private(set) var tagSuggestions: [TagTypeahead.Suggestion] = []
    /// `true` when a token is active and tags exist but none match — the view
    /// shows the disabled `No tag found` row. Distinct from "no suggestions"
    /// because a zero-tag account never shows the picker at all (spec).
    @Published private(set) var showNoTagMatch = false
    /// `true` while the first tag fetch is in flight *and* a token is active,
    /// so the suggestion surface can show a small inline spinner.
    @Published private(set) var isLoadingTags = false

    /// The token the current suggestions were computed for; consumed by
    /// `acceptSuggestion(_:)` to splice the replacement in.
    private var activeToken: TagTypeahead.ActiveToken?
    /// All tags for the account, fetched once per editor session on the first
    /// `#`. `nil` = not fetched yet. A failed fetch resets to `nil` so a later
    /// token retries — tag loading must never block typing (spec), so there
    /// is no error surface here.
    private var loadedTags: [Tag]?
    private var tagLoadTask: Task<Void, Never>?

    let mode: Mode
    private let noteType: NoteType
    private let originalContent: String
    private let noteService: any NoteServiceProtocol
    /// Source for typeahead suggestions. Optional so screens that never had
    /// a tag stack (previews, older call sites) keep working: `nil` simply
    /// disables the typeahead.
    private let tagService: (any TagServiceProtocol)?
    /// Called with the server's copy after a successful save, so the owning
    /// screen can refresh its list/detail without another round-trip.
    private let onSaved: (Note) -> Void

    init(
        noteService: any NoteServiceProtocol,
        tagService: (any TagServiceProtocol)? = nil,
        note: Note? = nil,
        noteType: NoteType = .blinko,
        onSaved: @escaping (Note) -> Void = { _ in }
    ) {
        self.noteService = noteService
        self.tagService = tagService
        self.mode = note.map { .edit(id: $0.id) } ?? .create
        self.noteType = note?.type ?? noteType
        self.content = note?.content ?? ""
        self.originalContent = note?.content ?? ""
        self.onSaved = onSaved
    }

    /// A save is allowed once there is real text and it differs from what the
    /// server already has (edits of pure whitespace churn are pointless).
    var canSave: Bool {
        !isSaving
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && content != originalContent
    }

    /// `true` when leaving now would lose typed text — the view uses it to
    /// ask before discarding.
    var hasUnsavedChanges: Bool {
        content != originalContent
            && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Persists the draft. Returns `true` on success so the view knows to
    /// dismiss; on failure the draft stays in `content` for retry.
    @discardableResult
    func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let saved: Note
            switch mode {
            case .create:
                saved = try await noteService.createNote(content: content, type: noteType)
            case .edit(let id):
                saved = try await noteService.updateContent(id: id, content: content)
            }
            clearError()
            onSaved(saved)
            return true
        } catch {
            present(error)
            return false
        }
    }

    // MARK: - Tag typeahead

    /// Recomputes the suggestion state for the caret position the view just
    /// reported. Call on every content or selection change.
    ///
    /// Typing stays fully responsive: the first `#` kicks off a background
    /// tag fetch, and until it lands the surface only shows a spinner. A
    /// zero-tag account or a caret outside any token clears everything.
    func caretMoved(toUTF16Offset offset: Int) {
        guard tagService != nil else { return }
        guard let token = TagTypeahead.activeToken(in: content, caretUTF16Offset: offset) else {
            dismissSuggestions()
            return
        }
        activeToken = token
        guard let tags = loadedTags else {
            // First `#` of the session: fetch once, then re-filter for
            // whatever token is active when the payload lands.
            isLoadingTags = true
            tagSuggestions = []
            showNoTagMatch = false
            loadTagsIfNeeded()
            return
        }
        refilter(for: token, tags: tags)
    }

    /// Replaces the active hashtag token with the chosen tag (plus trailing
    /// space) and returns the caret offset the view should move to, or `nil`
    /// when there is no active token to replace.
    func acceptSuggestion(_ suggestion: TagTypeahead.Suggestion) -> Int? {
        guard let token = activeToken,
              let insertion = TagTypeahead.insert(suggestion, replacing: token, in: content)
        else {
            dismissSuggestions()
            return nil
        }
        content = insertion.content
        dismissSuggestions()
        return insertion.caretUTF16Offset
    }

    /// Hides the suggestion surface without touching content — space/newline
    /// termination is a natural consequence of the token parser, and Cancel/
    /// focus-loss call this directly.
    func dismissSuggestions() {
        activeToken = nil
        tagSuggestions = []
        showNoTagMatch = false
        isLoadingTags = false
    }

    private func refilter(for token: TagTypeahead.ActiveToken, tags: [Tag]) {
        isLoadingTags = false
        guard !tags.isEmpty else {
            // Zero tags on the account: no picker at all, free typing (spec).
            tagSuggestions = []
            showNoTagMatch = false
            return
        }
        let matches = TagTypeahead.suggestions(matching: token.query, in: tags)
        tagSuggestions = matches
        showNoTagMatch = matches.isEmpty
    }

    private func loadTagsIfNeeded() {
        guard tagLoadTask == nil, let tagService else { return }
        tagLoadTask = Task { [weak self] in
            defer { self?.tagLoadTask = nil }
            do {
                let tags = try await tagService.fetchTags()
                guard let self else { return }
                self.loadedTags = tags
                if let token = self.activeToken {
                    self.refilter(for: token, tags: tags)
                }
            } catch {
                // Never block typing over a failed tag fetch; drop the
                // spinner and let a future `#` retry.
                guard let self else { return }
                self.isLoadingTags = false
                self.tagSuggestions = []
                self.showNoTagMatch = false
            }
        }
    }

    private func present(_ error: any Error) {
        errorMessage = error.localizedDescription
        if case APIError.unauthorized = error {
            requiresReauthentication = true
        } else {
            showError = true
        }
    }

    private func clearError() {
        errorMessage = ""
        showError = false
    }
}
