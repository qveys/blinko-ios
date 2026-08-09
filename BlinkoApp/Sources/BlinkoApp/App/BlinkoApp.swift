import SwiftUI

@main
struct BlinkoApp: App {
    @StateObject private var appCoordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appCoordinator)
                .task {
                    await appCoordinator.restoreSession()
                }
        }
    }
}
