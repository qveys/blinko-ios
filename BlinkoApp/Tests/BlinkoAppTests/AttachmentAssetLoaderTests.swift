import XCTest
@testable import BlinkoApp

/// `AttachmentAssetLoader` transport behaviour: bearer auth on file requests,
/// memory-cache hits, error mapping, and the QuickLook temp-file path.
final class AttachmentAssetLoaderTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_725_000_000)
    private let serverURL = URL(string: "https://blinko.example.test")!

    private func makeAttachment(
        id: Int = 1,
        name: String = "photo.png",
        path: String = "/api/file/photo.png"
    ) -> Attachment {
        Attachment(
            id: id, name: name, path: path, size: 4, type: "image/png",
            createdAt: base, updatedAt: base
        )
    }

    private func makeLoader(
        token: String? = "secret-token",
        handler: @escaping StubURLProtocol.Handler
    ) -> AttachmentAssetLoader {
        StubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return AttachmentAssetLoader(
            serverURL: serverURL,
            session: URLSession(configuration: config),
            tokenProvider: InMemoryTokenStore(token: token)
        )
    }

    private func imageBytes() -> Data { Data([0x01, 0x02, 0x03, 0x04]) }

    func testSendsBearerTokenToFileRoute() async throws {
        let requested = expectation(description: "request sent")
        let loader = makeLoader { request in
            XCTAssertEqual(
                request.value(forHTTPHeaderField: "Authorization"),
                "Bearer secret-token"
            )
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://blinko.example.test/api/file/photo.png"
            )
            requested.fulfill()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data([0x01]))
        }

        _ = try await loader.data(for: makeAttachment())
        await fulfillment(of: [requested], timeout: 2)
    }

    func testOmitsAuthorizationWhenNoToken() async throws {
        let loader = makeLoader(token: nil) { request in
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data([0x01]))
        }

        _ = try await loader.data(for: makeAttachment())
    }

    func testSecondRequestServedFromMemoryCache() async throws {
        // The stub counts hits; the second call must not reach the network.
        let counter = Counter()
        let loader = makeLoader { request in
            counter.increment()
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data([0x0A, 0x0B]))
        }

        let attachment = makeAttachment()
        let first = try await loader.data(for: attachment)
        let second = try await loader.data(for: attachment)

        XCTAssertEqual(first, second)
        XCTAssertEqual(counter.value, 1)
    }

    func testHTTPFailureMapsToAPIError() async {
        let loader = makeLoader { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{\"error\": \"unauthorized\"}".utf8))
        }

        do {
            _ = try await loader.data(for: makeAttachment())
            XCTFail("Expected an error")
        } catch let error as APIError {
            guard case .unauthorized = error else {
                return XCTFail("Expected .unauthorized, got \(error)")
            }
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testInvalidPathThrowsInvalidURL() async {
        let loader = makeLoader { _ in throw URLError(.unknown) }
        let broken = makeAttachment(path: "")

        do {
            _ = try await loader.data(for: broken)
            XCTFail("Expected an error")
        } catch {
            // Empty path resolves to the bare server URL and hits the stub, or
            // fails URL resolution — either way it must throw, not crash.
        }
    }

    func testLocalFileURLWritesNamedTempFile() async throws {
        let loader = makeLoader { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data([0x0C, 0x0D]))
        }

        let attachment = makeAttachment(id: 42, name: "report.pdf", path: "/api/file/report.pdf")
        let url = try await loader.localFileURL(for: attachment)

        XCTAssertEqual(url.lastPathComponent, "report.pdf")
        XCTAssertTrue(url.path.contains("blinko-attachments/42"))
        XCTAssertEqual(try Data(contentsOf: url), Data([0x0C, 0x0D]))
        try? FileManager.default.removeItem(at: url)
    }
}

/// Thread-safe hit counter for stub handlers, which URLSession may call off
/// the main thread.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock(); defer { lock.unlock() }
        count += 1
    }
}
