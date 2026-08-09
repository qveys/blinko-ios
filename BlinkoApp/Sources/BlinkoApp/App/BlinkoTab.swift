import SwiftUI

/// Top-level destinations in the authenticated app shell.
///
/// Each case is the canonical identifier for a tab — used in the SwiftUI
/// `TabView`, in tests, and in deep links (see `BlinkoTab.routeID`).
enum BlinkoTab: String, CaseIterable, Identifiable, Hashable {
    case home
    case notes
    case search
    case settings

    var id: String { rawValue }

    /// Stable identifier used by deep links and persisted navigation state.
    /// Format is `blinko://tab/<value>` for universal links and
    /// `tab=<value>` for in-app paths.
    var routeID: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .notes: return "Notes"
        case .search: return "Search"
        case .settings: return "Settings"
        }
    }

    /// SF Symbol used for the tab bar icon. Selected / unselected variants are
    /// the same symbol — SwiftUI's `TabView` applies fill automatically.
    var systemImage: String {
        switch self {
        case .home: return "house"
        case .notes: return "note.text"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }

    /// Order in which tabs appear, left to right.
    static let displayOrder: [BlinkoTab] = [.home, .notes, .search, .settings]

    /// Returns the tab for a raw route id, or `nil` if the value is unknown.
    /// Lets future screens safely parse user-supplied deep links.
    static func tab(forRouteID id: String) -> BlinkoTab? {
        BlinkoTab(rawValue: id)
    }
}

/// Observable selection state for `MainTabView`.
///
/// Held in a dedicated model so the choice can be inspected by tests and
/// (later) persisted across launches without coupling `MainTabView` to any
/// specific storage.
@MainActor
final class TabSelection: ObservableObject {
    @Published var current: BlinkoTab

    init(initial: BlinkoTab = .home) {
        self.current = initial
    }

    /// Switches the active tab. No-op when the requested tab is already active.
    func select(_ tab: BlinkoTab) {
        guard current != tab else { return }
        current = tab
    }

    /// Switches by raw route id. Returns `true` if the id matched a known tab.
    @discardableResult
    func select(routeID: String) -> Bool {
        guard let tab = BlinkoTab.tab(forRouteID: routeID) else { return false }
        select(tab)
        return true
    }
}
