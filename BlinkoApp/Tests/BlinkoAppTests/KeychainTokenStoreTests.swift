import XCTest
@testable import BlinkoApp

final class KeychainTokenStoreTests: XCTestCase {
    private var store: KeychainTokenStore!
    // Use a unique service per test run so Keychain leftovers from prior runs
    // don't pollute results. The test target runs on the simulator so the
    // Keychain is accessible without entitlements.
    private let service = "com.blinko.ios.tests.\(UUID().uuidString)"

    override func setUp() async throws {
        store = KeychainTokenStore(service: service, account: "api-token")
        // Start clean.
        await store.setToken(nil)
    }

    override func tearDown() async throws {
        await store.setToken(nil)
    }

    func testSaveAndLoad() async throws {
        await store.setToken("tok_abc123")
        let addStatus = await store.lastAddStatus
        let loaded = await store.token
        let readStatus = await store.lastReadStatus
        XCTAssertEqual(loaded, "tok_abc123", "add=\(addStatus) read=\(readStatus)")
    }

    func testOverwrite() async throws {
        await store.setToken("first")
        await store.setToken("second")
        let addStatus = await store.lastAddStatus
        let loaded = await store.token
        let readStatus = await store.lastReadStatus
        XCTAssertEqual(loaded, "second", "add=\(addStatus) read=\(readStatus)")
    }

    func testClear() async throws {
        await store.setToken("tok_abc123")
        await store.setToken(nil)
        let loaded = await store.token
        XCTAssertNil(loaded)
    }

    func testEmptyOnFirstUse() async throws {
        let loaded = await store.token
        XCTAssertNil(loaded)
    }

    func testConformsToTokenStore() {
        // Compile-time check: KeychainTokenStore satisfies both protocols.
        let _: any TokenStore = store
        let _: any TokenProviding = store
    }
}
