import SwiftUI

@MainActor
final class AppCoordinator: ObservableObject {
    @Published var isAuthenticated = false
    @Published var serverURL: URL?

    func configure(serverURL: URL) {
        self.serverURL = serverURL
    }
}
