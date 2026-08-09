import Foundation

extension Tag {
    /// A short, human-friendly label for chip display.
    ///
    /// Tags are stored one row per path segment, so a nested tag's `name` is the
    /// leaf only (e.g. `projects`, not `work/projects`). This returns that leaf
    /// name; the full path is rebuilt by walking `parent` when a wider context
    /// is available, which the card chip row does not have.
    var displayName: String { name }
}
