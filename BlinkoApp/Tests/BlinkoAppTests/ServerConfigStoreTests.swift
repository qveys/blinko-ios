import XCTest
@testable import BlinkoApp

/// Tests for `ServerConfigStore` persistence contract.
///
/// Validated against `InMemoryServerConfigStore`, the same seam that
/// `AppCoordinator` programs against in tests. The `UserDefaults`-backed
/// production implementation is not exercised here to avoid polluting the
/// test host's standard suite with real keys.
final class ServerConfigStoreTests: XCTestCase {

    private let sampleURL = URL(string: "https://blinko.example.com")!
    private let otherURL  = URL(string: "https://blinko2.example.com")!

    // MARK: - InMemoryServerConfigStore

    func testInitiallyNil() {
        let store = InMemoryServerConfigStore()
        XCTAssertNil(store.serverURL)
    }

    func testSaveAndLoad() {
        let store = InMemoryServerConfigStore()
        store.save(serverURL: sampleURL)
        XCTAssertEqual(store.serverURL, sampleURL)
    }

    func testOverwrite() {
        let store = InMemoryServerConfigStore(serverURL: sampleURL)
        store.save(serverURL: otherURL)
        XCTAssertEqual(store.serverURL, otherURL)
    }

    func testClearRemovesURL() {
        let store = InMemoryServerConfigStore(serverURL: sampleURL)
        store.clear()
        XCTAssertNil(store.serverURL)
    }

    func testClearWhenAlreadyNilIsIdempotent() {
        let store = InMemoryServerConfigStore()
        store.clear() // should not crash
        XCTAssertNil(store.serverURL)
    }

    // MARK: - UserDefaultsServerConfigStore (isolated suite)

    /// Exercises the UserDefaults-backed store using a dedicated isolated suite
    /// so production defaults are never touched and parallel test runs don't
    /// interfere with each other.
    func testUserDefaultsRoundTrip() {
        let suiteName = "com.blinko.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsServerConfigStore(defaults: defaults)

        XCTAssertNil(store.serverURL, "Fresh suite should have no URL")
        store.save(serverURL: sampleURL)
        XCTAssertEqual(store.serverURL, sampleURL)
        store.clear()
        XCTAssertNil(store.serverURL)
    }

    func testUserDefaultsOverwrite() {
        let suiteName = "com.blinko.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsServerConfigStore(defaults: defaults)
        store.save(serverURL: sampleURL)
        store.save(serverURL: otherURL)
        XCTAssertEqual(store.serverURL, otherURL)
    }
}
