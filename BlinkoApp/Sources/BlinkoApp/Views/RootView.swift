import SwiftUI

struct RootView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        if coordinator.isAuthenticated {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}
