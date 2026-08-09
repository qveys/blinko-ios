import SwiftUI

/// Tab bar shell for the authenticated app.
///
/// Wraps each top-level destination in its own `NavigationStack` so deep
/// navigation state stays isolated per tab. Receives the live service
/// container so tabs can present real screens (Home) or future screens that
/// depend on the same service stack.
struct MainTabView: View {
    @EnvironmentObject private var selection: TabSelection

    private let services: ServiceContainer

    init(services: ServiceContainer) {
        self.services = services
    }

    var body: some View {
        TabView(selection: $selection.current) {
            ForEach(BlinkoTab.displayOrder) { tab in
                destination(for: tab)
                    .tabItem {
                        Label(tab.title, systemImage: tab.systemImage)
                    }
                    .tag(tab)
            }
        }
    }

    @ViewBuilder
    private func destination(for tab: BlinkoTab) -> some View {
        switch tab {
        case .home:
            HomeView(noteService: services.noteService)
        case .notes:
            NavigationStack { PlaceholderView(title: tab.title, systemImage: tab.systemImage) }
        case .search:
            NavigationStack { PlaceholderView(title: tab.title, systemImage: tab.systemImage) }
        case .settings:
            NavigationStack { SettingsTabView() }
        }
    }
}
