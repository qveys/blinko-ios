import XCTest
@testable import BlinkoApp

// MARK: - Helpers

/// URLProtocol subclass that lets a test control what URLSession returns.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)

    static var handler: Handler?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = StubURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeClient(
    handler: @escaping StubURLProtocol.Handler,
    retryPolicy: RetryPolicy = .none
) -> URLSessionHTTPClient {
    StubURLProtocol.handler = handler
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    let session = URLSession(configuration: config)
    return URLSessionHTTPClient(
        baseURL: URL(string: "https://example.test")!,
        session: session,
        retryPolicy: retryPolicy
    )
}

private func ok200(data: Data = Data("{}".utf8)) -> StubURLProtocol.Handler {
    { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, data)
    }
}

// MARK: - Stall detection

final class HTTPClientStallTests: XCTestCase {

    struct Empty: Decodable {}

    func testTimedOutURLErrorMapsToTimedOutAPIError() async throws {
        let client = makeClient { _ in throw URLError(.timedOut) }

        do {
            let _: Empty = try await client.perform(
                APIRequest(path: "/test", method: .get, requiresAuth: false)
            )
            XCTFail("Expected timedOut error")
        } catch let error as APIError {
            XCTAssertEqual(error, .timedOut)
        }
    }

    func testTimedOutIsRetryable() {
        XCTAssertTrue(APIError.timedOut.isRetryable)
    }

    func testTimedOutIsDistinctFromTransport() {
        // timedOut must not collapse into the generic transport bucket
        if case .transport = APIError.timedOut {
            XCTFail("timedOut should not be a transport error")
        }
    }

    func testTimedOutHasLocalizedDescription() {
        XCTAssertFalse(APIError.timedOut.errorDescription?.isEmpty ?? true)
    }

    func testTimedOutIsRetriedOnSubsequentSuccess() async throws {
        var callCount = 0
        let client = makeClient(
            handler: { request in
                callCount += 1
                if callCount == 1 { throw URLError(.timedOut) }
                return try ok200()(request)
            },
            retryPolicy: RetryPolicy(
                maxRetries: 1,
                baseDelay: .zero,
                maxDelay: .zero
            )
        )

        let _: Empty = try await client.perform(
            APIRequest(path: "/test", method: .get, requiresAuth: false)
        )
        XCTAssertEqual(callCount, 2)
    }

    func testCancelledURLErrorMapsToAPIErrorCancelled() async throws {
        let client = makeClient { _ in throw URLError(.cancelled) }

        do {
            let _: Empty = try await client.perform(
                APIRequest(path: "/test", method: .get, requiresAuth: false)
            )
            XCTFail("Expected cancelled error")
        } catch let error as APIError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testTransportErrorsAreDistinctFromTimedOut() async throws {
        let client = makeClient { _ in throw URLError(.networkConnectionLost) }

        do {
            let _: Empty = try await client.perform(
                APIRequest(path: "/test", method: .get, requiresAuth: false)
            )
            XCTFail("Expected transport error")
        } catch let error as APIError {
            if case .transport = error { /* pass */ } else {
                XCTFail("Expected .transport, got \(error)")
            }
        }
    }
}
