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

    let mode: Mode
    private let noteType: NoteType
    private let originalContent: String
    private let noteService: any NoteServiceProtocol
    /// Called with the server's copy after a successful save, so the owning
    /// screen can refresh its list/detail without another round-trip.
    private let onSaved: (Note) -> Void

    init(
        noteService: any NoteServiceProtocol,
        note: Note? = nil,
        noteType: NoteType = .blinko,
        onSaved: @escaping (Note) -> Void = { _ in }
    ) {
        self.noteService = noteService
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

    // MARK: - Toolbar formatting (BLI-60)

    /// The current cursor selection in `content`, kept in sync by the view via
    /// a `TextEditor` binding. The toolbar acts on this range; when it's empty
    /// (collapsed caret) the format delimiters are still inserted and the
    /// selection advances to sit between them.
    ///
    /// Stored as `(Int, Int)` offsets rather than `Range<String.Index>` so
    /// this `ObservableObject` stays `Sendable`-compatible and the view can
    /// bind a plain integer pair without importing `SwiftUI` here.
    var selectionOffsets: (lower: Int, upper: Int) = (0, 0)

    /// Applies an inline style (bold/italic/code) at the current selection.
    /// Idempotent: toggling a style that already wraps the selection removes it.
    func applyInline(_ style: MarkdownFormatting.InlineStyle) {
        let result = MarkdownFormatting.toggleInline(
            style,
            in: content,
            selection: selection(in: content)
        )
        content = result.text
        selectionOffsets = (
            lower: content.distance(from: content.startIndex, to: result.selection.lowerBound),
            upper: content.distance(from: content.startIndex, to: result.selection.upperBound)
        )
    }

    /// Applies a heading level at the lines touched by the current selection.
    /// Idempotent: the same level applied twice strips the marker.
    func applyHeading(level: Int) {
        let result = MarkdownFormatting.toggleHeading(
            level: level,
            in: content,
            selection: selection(in: content)
        )
        content = result.text
        selectionOffsets = (
            lower: content.distance(from: content.startIndex, to: result.selection.lowerBound),
            upper: content.distance(from: content.startIndex, to: result.selection.upperBound)
        )
    }

    /// Converts the stored integer offsets back to a `String.Index` range,
    /// clamped to `content.startIndex...content.endIndex`.
    private func selection(in text: String) -> Range<String.Index> {
        let lower = text.index(
            text.startIndex,
            offsetBy: min(selectionOffsets.lower, text.count),
            limitedBy: text.endIndex
        ) ?? text.endIndex
        let upper = text.index(
            text.startIndex,
            offsetBy: min(selectionOffsets.upper, text.count),
            limitedBy: text.endIndex
        ) ?? text.endIndex
        return lower..<upper
    }

    // MARK: - Save

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
