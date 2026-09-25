import XCTest
@testable import BlinkoApp

/// Exercises `AttachmentService` against a stubbed `URLSession`, asserting the
/// exact wire shape Blinko's hand-written `file/upload` Express route expects.
final class AttachmentServiceTests: XCTestCase {

    private func makeService(
        token: String? = "test-token",
        retryPolicy: RetryPolicy = .none,
        handler: @escaping StubURLProtocol.Handler
    ) -> AttachmentService {
        StubURLProtocol.handler = handler
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let client = URLSessionHTTPClient(
            baseURL: URL(string: "https://example.test/api")!,
            session: URLSession(configuration: config),
            tokenProvider: InMemoryTokenStore(token: token),
            retryPolicy: retryPolicy
        )
        return AttachmentService(httpClient: client)
    }

    private static let successBody = Data("""
    {
      "Message": "Success",
      "status": 200,
      "filePath": "/api/file/1714746000-photo.png",
      "fileName": "1714746000-photo.png",
      "type": "image/png",
      "size": 3
    }
    """.utf8)

    private func response(_ status: Int, for request: URLRequest) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }

    // MARK: - Request shape

    func testUploadSendsMultipartPostToUploadPath() async throws {
        let captured = CapturedRequest()
        let service = makeService { request in
            captured.store(request)
            return (self.response(200, for: request), Self.successBody)
        }

        _ = try await service.upload(
            data: Data("png".utf8),
            filename: "photo.png",
            mimeType: "image/png"
        )

        let request = try XCTUnwrap(captured.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/file/upload")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")

        let contentType = try XCTUnwrap(request.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))

        let body = try XCTUnwrap(captured.bodyString)
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertTrue(body.contains("--\(boundary)\r\n"))
        XCTAssertTrue(body.contains("Content-Disposition: form-data; name=\"file\"; filename=\"photo.png\""))
        XCTAssertTrue(body.contains("Content-Type: image/png"))
        XCTAssertTrue(body.contains("\r\n\r\npng\r\n"))
        XCTAssertTrue(body.hasSuffix("--\(boundary)--\r\n"))
    }

    func testUploadStripsQuotesAndNewlinesFromFilename() async throws {
        let captured = CapturedRequest()
        let service = makeService { request in
            captured.store(request)
            return (self.response(200, for: request), Self.successBody)
        }

        _ = try await service.upload(
            data: Data([0x1]),
            filename: "we\"ird\r\nname.png",
            mimeType: "image/png"
        )

        let body = try XCTUnwrap(captured.bodyString)
        XCTAssertTrue(body.contains("filename=\"weirdname.png\""))
    }

    // MARK: - Response decoding

    func testUploadDecodesSuccessResponse() async throws {
        let service = makeService { request in
            (self.response(200, for: request), Self.successBody)
        }

        let upload = try await service.upload(
            data: Data("png".utf8),
            filename: "photo.png",
            mimeType: "image/png"
        )

        XCTAssertEqual(upload.path, "/api/file/1714746000-photo.png")
        XCTAssertEqual(upload.name, "1714746000-photo.png")
        XCTAssertEqual(upload.type, "image/png")
        XCTAssertEqual(upload.size, 3)
    }

    // MARK: - Failures

    func testUploadWithoutTokenFailsBeforeSendingAnything() async {
        let captured = CapturedRequest()
        let service = makeService(token: nil) { request in
            captured.store(request)
            return (self.response(500, for: request), Data())
        }

        do {
            _ = try await service.upload(data: Data(), filename: "x", mimeType: "text/plain")
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(message: nil))
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
        XCTAssertNil(captured.request, "No request should be sent without a token")
    }

    func testUploadMapsServer401ToUnauthorized() async {
        // File routes use the `{error}` envelope, not `{message}`.
        let service = makeService { request in
            (self.response(401, for: request), Data(#"{ "error": "Unauthorized" }"#.utf8))
        }

        do {
            _ = try await service.upload(data: Data(), filename: "x", mimeType: "text/plain")
            XCTFail("Expected unauthorized")
        } catch let error as APIError {
            XCTAssertEqual(error, .unauthorized(message: "Unauthorized"))
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testUploadSurfaces500AsRetryableServerError() async {
        let service = makeService { request in
            (self.response(500, for: request), Data(#"{ "error": "Upload failed" }"#.utf8))
        }

        do {
            _ = try await service.upload(data: Data(), filename: "x", mimeType: "text/plain")
            XCTFail("Expected server error")
        } catch let error as APIError {
            XCTAssertEqual(error, .server(statusCode: 500, message: "Upload failed", code: nil))
            XCTAssertTrue(error.isRetryable)
        } catch {
            XCTFail("Expected APIError, got \(error)")
        }
    }

    func testUploadRetriesTransientFailureAndSucceeds() async throws {
        let counter = CallCounter()
        let service = makeService(
            retryPolicy: RetryPolicy(maxRetries: 1, baseDelay: .zero, maxDelay: .zero)
        ) { request in
            if counter.increment() == 1 {
                return (self.response(500, for: request), Data(#"{ "error": "Upload failed" }"#.utf8))
            }
            return (self.response(200, for: request), Self.successBody)
        }

        let upload = try await service.upload(
            data: Data("png".utf8),
            filename: "photo.png",
            mimeType: "image/png"
        )

        XCTAssertEqual(upload.name, "1714746000-photo.png")
        XCTAssertEqual(counter.value, 2)
    }
}

// MARK: - Capture helpers

/// Lock-guarded capture of the request the stub saw, safe to fill from
/// URLSession's loading thread and read from the test.
private final class CapturedRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var storedRequest: URLRequest?
    private var storedBody: Data?

    func store(_ request: URLRequest) {
        // URLSession moves httpBody into a stream before the protocol sees it,
        // so drain the stream while it is still available.
        let body = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                guard read > 0 else { break }
                data.append(buffer, count: read)
            }
            return data
        }
        lock.lock()
        defer { lock.unlock() }
        storedRequest = request
        storedBody = body
    }

    var request: URLRequest? {
        lock.lock()
        defer { lock.unlock() }
        return storedRequest
    }

    var bodyString: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedBody.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Thread-safe call counter for retry assertions.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
