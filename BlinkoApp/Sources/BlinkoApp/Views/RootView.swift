import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        // Services only exist once a server URL is configured, so an
        // unconfigured app always lands on onboarding.
        if coordinator.isAuthenticated, let services = coordinator.services {
            HomeView(noteService: services.noteService)
        } else {
            OnboardingView()
        }
    }
}
