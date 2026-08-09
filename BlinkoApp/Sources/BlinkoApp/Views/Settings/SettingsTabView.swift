import SwiftUI

/// Settings tab — currently exposes sign-out. The shell is intentionally
/// minimal: more settings arrive with their owning tickets (account, server
/// switching, sync controls).
struct SettingsTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isSigningOut = false

    var body: some View {
        Form {
            Section("Account") {
                if let user = coordinator.currentUser {
                    LabeledContent("Signed in as", value: user.displayName)
                } else {
                    LabeledContent("Status", value: "Authenticated")
                }
            }

            Section {
                Button(role: .destructive) {
                    Task { await signOut() }
                } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                        if isSigningOut { Spacer(); ProgressView() }
                    }
                }
                .disabled(isSigningOut)
            }
        }
        .navigationTitle("Settings")
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        await coordinator.signOut()
    }
}
