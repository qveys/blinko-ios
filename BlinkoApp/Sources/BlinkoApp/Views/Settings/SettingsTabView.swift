import SwiftUI

/// Settings tab — shows server connection details, account identity, and sign-out.
struct SettingsTabView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var isSigningOut = false
    @State private var showSignOutConfirmation = false

    var body: some View {
        Form {
            serverSection
            accountSection
            signOutSection
        }
        .navigationTitle("Settings")
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task { await signOut() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to enter your server details to sign in again.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var serverSection: some View {
        Section("Server") {
            if let url = coordinator.serverURL {
                LabeledContent("URL", value: url.absoluteString)
                    .textSelection(.enabled)
            } else {
                LabeledContent("URL", value: "Not configured")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        Section("Account") {
            if let user = coordinator.currentUser {
                LabeledContent("Signed in as", value: user.displayName)
                if user.isSuperAdmin {
                    Label("Admin", systemImage: "shield.lefthalf.filled")
                        .foregroundStyle(.secondary)
                        .font(.footnote)
                }
            } else {
                LabeledContent("Status", value: "Authenticated")
            }
        }
    }

    @ViewBuilder
    private var signOutSection: some View {
        Section {
            Button(role: .destructive) {
                showSignOutConfirmation = true
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

    // MARK: - Actions

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        await coordinator.signOut()
    }
}
