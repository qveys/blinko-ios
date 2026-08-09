import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    /// Owned here (not inside `MainTabView`) so tab selection resets to Home
    /// whenever the shell is torn down by a sign-out and rebuilt on sign-in.
    @StateObject private var tabSelection = TabSelection()

    var body: some View {
        Group {
            // Services only exist once a server URL is configured, so an
            // unconfigured app always lands on onboarding.
            if coordinator.isAuthenticated, let services = coordinator.services {
                MainTabView(services: services)
                    .environmentObject(tabSelection)
            } else {
                OnboardingView()
            }
        }
        // Attached outside the branch so it still fires when sign-out removes
        // the tab shell: the next sign-in starts from Home, not wherever the
        // previous session happened to end.
        .onChange(of: coordinator.isAuthenticated) { _, authenticated in
            if !authenticated { tabSelection.select(.home) }
        }
    }
}
