import SwiftUI
import UIKit

/// A `UITextView` wrapper for the note editor.
///
/// SwiftUI's `TextEditor` cannot report the caret position on iOS 17, and the
/// hashtag typeahead (BLI-39) is caret-driven: the suggestion state depends on
/// which token the insertion point sits inside. This representable reports
/// every content/selection change as a UTF-16 caret offset and supports the
/// one programmatic move the feature needs — placing the caret after an
/// accepted suggestion.
struct MarkdownTextView: UIViewRepresentable {
    @Binding var text: String
    /// Set to move the caret (UTF-16 offset); consumed and reset to `nil`
    /// once applied, so SwiftUI state stays the single source of truth.
    @Binding var caretRequest: Int?
    @Binding var isFocused: Bool
    /// Fired with the caret's UTF-16 offset after any edit or selection
    /// change. Collapsed selections only — a ranged selection reports its
    /// end, which the token parser treats like any other caret.
    var onCaretChange: (Int) -> Void = { _ in }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        // Match TextEditor's previous behavior: autocorrection on, and give
        // the text a little breathing room from the screen edge.
        view.textContainerInset = UIEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        view.accessibilityLabel = "Note content"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        // Keep the coordinator's copy fresh — closures like `onCaretChange`
        // may capture new state on each SwiftUI update.
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
        }
        if let caret = caretRequest {
            let location = min(caret, view.text.utf16.count)
            view.selectedRange = NSRange(location: location, length: 0)
            // Clear outside the update pass; mutating state during
            // updateUIView is undefined behavior in SwiftUI.
            let request = _caretRequest
            DispatchQueue.main.async { request.wrappedValue = nil }
        }
        if isFocused, !view.isFirstResponder, view.window != nil {
            view.becomeFirstResponder()
        } else if !isFocused, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        fileprivate var parent: MarkdownTextView

        init(_ parent: MarkdownTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.onCaretChange(textView.selectedRange.upperBound)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            // Skip the callback while SwiftUI is pushing text in; only real
            // user/selection events should drive the typeahead.
            guard textView.isFirstResponder else { return }
            parent.onCaretChange(textView.selectedRange.upperBound)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if !parent.isFocused {
                DispatchQueue.main.async { self.parent.isFocused = true }
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if parent.isFocused {
                DispatchQueue.main.async { self.parent.isFocused = false }
            }
        }
    }
}
