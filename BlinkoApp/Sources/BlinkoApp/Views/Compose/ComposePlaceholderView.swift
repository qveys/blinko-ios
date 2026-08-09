import SwiftUI

/// Placeholder destination for the compose button.
///
/// BLI-20 owns the real editor (markdown body, type picker, save). Until then
/// the button still routes to a real screen so users can discover what the
/// tap does — the placeholder explains the scope and offers a `Cancel` to
/// return to the list.
struct ComposePlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Editor coming soon",
                systemImage: "square.and.pencil",
                description: Text("Creating and editing notes ships in a follow-up.")
            )
            Button("Done", action: dismiss.callAsFunction)
                .buttonStyle(.borderedProminent)
        }
        .padding()
        .navigationTitle("New Note")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview("Compose placeholder") {
    NavigationStack { ComposePlaceholderView() }
}
#endif
