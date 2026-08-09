import Combine
import XCTest
@testable import BlinkoApp

/// Covers the tab shell's model layer: identifiers, ordering, and selection.
///
/// `MainTabView` itself is a thin `TabView` wrapper, so exercising
/// `BlinkoTab` + `TabSelection` is the meaningful smoke test for tab
/// switching until a UI-test target exists (tracked in the issue as
/// "where feasible" — SwiftPM test targets can't host XCUITests).
@MainActor
final class TabNavigationTests: XCTestCase {

    // MARK: - BlinkoTab

    func testAllExpectedTabsExist() {
        XCTAssertEqual(
            Set(BlinkoTab.allCases),
            [.home, .notes, .search, .settings]
        )
    }

    func testDisplayOrderContainsEveryTabExactlyOnce() {
        XCTAssertEqual(BlinkoTab.displayOrder.count, BlinkoTab.allCases.count)
        XCTAssertEqual(Set(BlinkoTab.displayOrder), Set(BlinkoTab.allCases))
    }

    func testDisplayOrderStartsAtHome() {
        XCTAssertEqual(BlinkoTab.displayOrder.first, .home)
    }

    /// Route ids are a public contract (deep links, persisted state) — a
    /// rename would silently break saved links, so pin the exact strings.
    func testRouteIDsAreStable() {
        XCTAssertEqual(BlinkoTab.home.routeID, "home")
        XCTAssertEqual(BlinkoTab.notes.routeID, "notes")
        XCTAssertEqual(BlinkoTab.search.routeID, "search")
        XCTAssertEqual(BlinkoTab.settings.routeID, "settings")
    }

    func testRouteIDRoundTripsForEveryTab() {
        for tab in BlinkoTab.allCases {
            XCTAssertEqual(BlinkoTab.tab(forRouteID: tab.routeID), tab)
        }
    }

    func testUnknownRouteIDReturnsNil() {
        XCTAssertNil(BlinkoTab.tab(forRouteID: "profile"))
        XCTAssertNil(BlinkoTab.tab(forRouteID: ""))
        // Matching is case-sensitive: route ids are lowercase by contract.
        XCTAssertNil(BlinkoTab.tab(forRouteID: "Home"))
    }

    // MARK: - TabSelection

    func testDefaultsToHome() {
        XCTAssertEqual(TabSelection().current, .home)
    }

    func testSelectSwitchesTab() {
        let selection = TabSelection()

        selection.select(.search)

        XCTAssertEqual(selection.current, .search)
    }

    func testSelectByRouteIDSwitchesTab() {
        let selection = TabSelection()

        XCTAssertTrue(selection.select(routeID: "settings"))
        XCTAssertEqual(selection.current, .settings)
    }

    func testSelectByUnknownRouteIDKeepsCurrentTab() {
        let selection = TabSelection(initial: .notes)

        XCTAssertFalse(selection.select(routeID: "nope"))
        XCTAssertEqual(selection.current, .notes)
    }

    /// Re-selecting the active tab must not publish a change — SwiftUI would
    /// otherwise rebuild the tab's view tree for a no-op.
    func testReselectingCurrentTabDoesNotPublish() {
        let selection = TabSelection(initial: .search)
        var changes = 0
        let cancellable = selection.$current.dropFirst().sink { _ in changes += 1 }

        selection.select(.search)

        XCTAssertEqual(changes, 0)
        _ = cancellable
    }

    func testSwitchingThroughEveryTabLandsWhereExpected() {
        let selection = TabSelection()

        for tab in BlinkoTab.displayOrder {
            selection.select(tab)
            XCTAssertEqual(selection.current, tab)
        }
    }
}
