import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

/// A single API call.
///
/// Blinko's generated REST layer is POST-heavy: reads like `note/list` and
/// `note/detail` are `POST` with a JSON body, because they are tRPC mutations
/// and queries mapped onto HTTP.
struct APIRequest: Sendable {
    let path: String
    let method: HTTPMethod
    let body: (any Encodable & Sendable)?
    let queryItems: [URLQueryItem]
    /// Set false for endpoints that must not carry credentials.
    let requiresAuth: Bool

    init(
        path: String,
        method: HTTPMethod,
        body: (any Encodable & Sendable)? = nil,
        queryItems: [URLQueryItem] = [],
        requiresAuth: Bool = true
    ) {
        self.path = path
        self.method = method
        self.body = body
        self.queryItems = queryItems
        self.requiresAuth = requiresAuth
    }
}

protocol HTTPClient: Sendable {
    func perform<T: Decodable>(_ request: APIRequest) async throws -> T
    /// For endpoints whose response body we don't care about.
    func perform(_ request: APIRequest) async throws
}

/// Supplies the bearer token for authenticated requests.
///
/// Kept as a protocol so the token can live in the Keychain in the app and be
/// a plain value in tests.
protocol TokenProviding: Sendable {
    var token: String? { get async }
}

/// In-memory token holder. Real persistence lands with the auth ticket.
actor InMemoryTokenStore: TokenProviding {
    private var storedToken: String?

    init(token: String? = nil) {
        self.storedToken = token
    }

    var token: String? { storedToken }

    func setToken(_ token: String?) {
        storedToken = token
    }
}

/// How many times to retry, and how long to wait between attempts.
struct RetryPolicy: Sendable {
    /// Retries *after* the first attempt. `0` disables retrying.
    var maxRetries: Int
    /// Delay before the first retry; doubles each subsequent attempt.
    var baseDelay: Duration
    /// Upper bound on any single backoff delay.
    var maxDelay: Duration

    static let `default` = RetryPolicy(
        maxRetries: 2,
        baseDelay: .milliseconds(500),
        maxDelay: .seconds(4)
    )

    static let none = RetryPolicy(
        maxRetries: 0,
        baseDelay: .zero,
        maxDelay: .zero
    )

    /// Exponential backoff for a given attempt, capped at ``maxDelay``.
    func delay(forAttempt attempt: Int) -> Duration {
        guard attempt > 0 else { return .zero }
        let multiplier = 1 << (attempt - 1)
        let scaled = baseDelay * multiplier
        return scaled > maxDelay ? maxDelay : scaled
    }
}

/// `URLSession`-backed client for the Blinko REST API.
///
/// Every path passed in is relative to `/api` — see ``BlinkoAPI`` for the
/// endpoint constants.
final class URLSessionHTTPClient: HTTPClient {
    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: (any TokenProviding)?
    private let retryPolicy: RetryPolicy
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL,
        session: URLSession = .shared,
        tokenProvider: (any TokenProviding)? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.baseURL = baseURL
        self.session = session
        self.tokenProvider = tokenProvider
        self.retryPolicy = retryPolicy
        self.decoder = JSONDecoder.blinko
        self.encoder = JSONEncoder.blinko
    }

    func perform<T: Decodable>(_ request: APIRequest) async throws -> T {
        let data = try await performReturningData(request)
        // Endpoints declared `.output(z.any())` can answer with an empty body.
        if data.isEmpty, let empty = EmptyResponse() as? T {
            return empty
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func perform(_ request: APIRequest) async throws {
        _ = try await performReturningData(request)
    }

    private func performReturningData(_ request: APIRequest) async throws -> Data {
        var attempt = 0

        while true {
            do {
                // Rebuild per attempt so authenticated retries pick up a token
                // changed by a concurrent sign-in/PAT update while backing off.
                return try await send(try await makeURLRequest(request))
            } catch let error as APIError {
                guard error.isRetryable, attempt < retryPolicy.maxRetries else {
                    throw error
                }
                attempt += 1
                try await Task.sleep(for: retryPolicy.delay(forAttempt: attempt))
            }
        }
    }

    private func send(_ urlRequest: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError where error.code == .cancelled {
            throw APIError.cancelled
        } catch is CancellationError {
            throw APIError.cancelled
        } catch let error as URLError where error.code == .timedOut {
            throw APIError.timedOut
        } catch {
            throw APIError.transport(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.transport("The server sent a malformed response.")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = try? decoder.decode(APIErrorBody.self, from: data)
            throw APIError.from(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }

    private func makeURLRequest(_ request: APIRequest) async throws -> URLRequest {
        let path = request.path.hasPrefix("/") ? String(request.path.dropFirst()) : request.path
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else {
            throw APIError.invalidURL
        }
        if !request.queryItems.isEmpty {
            components.queryItems = request.queryItems
        }
        guard let url = components.url else { throw APIError.invalidURL }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = request.body {
            do {
                urlRequest.httpBody = try encoder.encode(body)
            } catch {
                throw APIError.decoding("Could not encode the request body.")
            }
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if request.requiresAuth {
            guard let token = await tokenProvider?.token, !token.isEmpty else {
                throw APIError.unauthorized(message: nil)
            }
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }
}

/// Stand-in for endpoints that return nothing useful.
struct EmptyResponse: Codable, Sendable {
    init() {}
    init(from decoder: any Decoder) throws {}
    func encode(to encoder: any Encoder) throws {}
}

extension JSONDecoder {
    /// Decoder configured for Blinko's wire format.
    static var blinko: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = Date.blinkoISO8601(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized date format: \(raw)"
                )
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    static var blinko: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension Date {
    /// Parses the timestamps Blinko emits.
    ///
    /// Postgres `Timestamptz(6)` serializes with fractional seconds
    /// (`2024-05-01T12:00:00.123Z`), but values that land exactly on a second
    /// come back without them. `ISO8601DateFormatter` will not accept both with
    /// one option set, so try the fractional variant first and fall back.
    static func blinkoISO8601(from string: String) -> Date? {
        if let date = fractionalISO8601Formatter.date(from: string) {
            return date
        }
        return plainISO8601Formatter.date(from: string)
    }
}

private let fractionalISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
}()

private let plainISO8601Formatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
}()
