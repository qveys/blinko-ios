import SwiftUI

/// Minimal placeholder shown by tabs that don't yet have a real screen.
///
/// Kept intentionally thin — the tickets owning Notes and Search will swap
/// their `MainTabView` cases from this placeholder to the real views.
struct PlaceholderView: View {
    let title: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(
            "\(title) coming soon",
            systemImage: systemImage,
            description: Text("This tab is a placeholder. Real functionality lands in a follow-up issue.")
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}
