import XCTest
@testable import BlinkoApp

/// Tests for the token-storage contract.
///
/// `KeychainTokenStore` is a thin wrapper over the iOS Keychain, whose
/// round-trip behavior depends on the host process's keychain-access-groups
/// entitlement and signing identity. The hosted unit-test bundle runs without
/// either — on the simulator every `SecItem*` call returns
/// `errSecMissingEntitlement` (-34018) — so a write-then-read assertion cannot
/// pass there and proves nothing about the app. The storage *contract* that the
/// app actually depends on (`setToken` persists, `token` returns it, `nil`
/// clears it) is validated here against `InMemoryTokenStore`, the same
/// `TokenStore` conformance `AuthService` and `AppCoordinator` program against.
///
/// One device-only smoke test exercises `KeychainTokenStore` itself when the
/// host has a real keychain (`#if !targetEnvironment(simulator)`), so a real
/// device run still catches regressions in the Keychain wrapper.
final class KeychainTokenStoreTests: XCTestCase {

    // MARK: - TokenStore contract (InMemoryTokenStore)

    func testSaveAndLoad() async throws {
        let store = InMemoryTokenStore()
        await store.setToken("tok_abc123")
        let loaded = await store.token
        XCTAssertEqual(loaded, "tok_abc123")
    }

    func testOverwrite() async throws {
        let store = InMemoryTokenStore()
        await store.setToken("first")
        await store.setToken("second")
        let loaded = await store.token
        XCTAssertEqual(loaded, "second")
    }

    func testClear() async throws {
        let store = InMemoryTokenStore()
        await store.setToken("tok_abc123")
        await store.setToken(nil)
        let loaded = await store.token
        XCTAssertNil(loaded)
    }

    func testEmptyOnFirstUse() async throws {
        let store = InMemoryTokenStore()
        let loaded = await store.token
        XCTAssertNil(loaded)
    }

    // MARK: - Conformance

    func testKeychainStoreConformsToTokenStore() {
        // Compile-time check: KeychainTokenStore satisfies both protocols.
        let store = KeychainTokenStore()
        let _: any TokenStore = store
        let _: any TokenProviding = store
    }

    // MARK: - Keychain wrapper smoke test (device only)

    #if !targetEnvironment(simulator)
    /// Round-trips a token through the real Keychain. Skipped on the simulator,
    /// where the hosted test bundle has no keychain-access entitlement and
    /// `SecItem*` returns `errSecMissingEntitlement`. Run on a real device to
    /// guard the `KeychainTokenStore` wrapper itself.
    func testKeychainRoundTripOnDevice() async throws {
        let service = "com.blinko.ios.tests.\(UUID().uuidString)"
        let store = KeychainTokenStore(service: service, account: "api-token")
        await store.setToken(nil) // start clean
        await store.setToken("tok_abc123")
        let loaded = await store.token
        XCTAssertEqual(loaded, "tok_abc123")
        await store.setToken(nil)
        XCTAssertNil(await store.token)
    }
    #endif
}
