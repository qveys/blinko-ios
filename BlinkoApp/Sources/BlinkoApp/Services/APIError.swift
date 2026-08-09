import Foundation

/// The error body Blinko's REST layer returns.
///
/// The generated `/api/v1/*` routes emit a **flat** object — `{message, code,
/// issues}` — not a tRPC-style `{error: {...}}` envelope. The hand-written
/// Express file routes instead emit `{error: "..."}` or `{message: "..."}`.
/// This decodes all three so callers get a usable message either way.
struct APIErrorBody: Decodable, Sendable {
    /// Human-readable message. Falls back to the `error` key for file routes.
    let message: String?
    /// tRPC error code, e.g. `UNAUTHORIZED`, `NOT_FOUND`, `FORBIDDEN`.
    let code: String?
    /// Zod validation issues, present only on input-validation failures.
    let issues: [Issue]?

    struct Issue: Decodable, Sendable {
        let message: String?
        let path: [String]?

        enum CodingKeys: String, CodingKey { case message, path }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            // Zod paths mix strings and array indices; normalize to strings.
            if var nested = try? container.nestedUnkeyedContainer(forKey: .path) {
                var components: [String] = []
                while !nested.isAtEnd {
                    if let text = try? nested.decode(String.self) {
                        components.append(text)
                    } else if let index = try? nested.decode(Int.self) {
                        components.append(String(index))
                    } else {
                        _ = try? nested.decode(AnyCodableSkip.self)
                    }
                }
                path = components
            } else {
                path = nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case message, code, issues, error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let direct = try container.decodeIfPresent(String.self, forKey: .message)
        let fileRouteStyle = try? container.decodeIfPresent(String.self, forKey: .error)
        message = direct ?? fileRouteStyle
        code = try container.decodeIfPresent(String.self, forKey: .code)
        issues = try container.decodeIfPresent([Issue].self, forKey: .issues)
    }

    /// Validation detail suitable for appending to a message.
    var validationDetail: String? {
        guard let issues, !issues.isEmpty else { return nil }
        return issues.compactMap { issue in
            guard let message = issue.message else { return nil }
            guard let path = issue.path, !path.isEmpty else { return message }
            return "\(path.joined(separator: ".")): \(message)"
        }.joined(separator: "; ")
    }
}

/// Placeholder used to step over values we do not need while decoding.
private struct AnyCodableSkip: Decodable {}

/// Errors surfaced by the networking layer.
enum APIError: Error, Equatable, Sendable {
    /// The configured server URL could not be turned into a request URL.
    case invalidURL
    /// No server has been configured yet.
    case notConfigured
    /// Authentication failed or the stored token is no longer valid (401).
    /// The user must sign in again — there is no refresh flow.
    case unauthorized(message: String?)
    /// The token is valid but lacks permission for this endpoint, or the
    /// instance is running in demo mode (403).
    case forbidden(message: String?)
    /// The requested resource does not exist (404).
    case notFound(message: String?)
    /// Input validation failed (400 with Zod issues).
    case validation(message: String, detail: String?)
    /// Any other non-2xx response.
    case server(statusCode: Int, message: String?, code: String?)
    /// The response body did not match the expected shape.
    case decoding(String)
    /// The request never completed — offline, DNS failure, timeout, TLS.
    case transport(String)
    /// The request was cancelled.
    case cancelled
    /// The server stopped sending data mid-transfer (stall timeout).
    case timedOut

    /// Whether retrying the identical request could plausibly succeed.
    ///
    /// 4xx responses are excluded: the same request will fail the same way.
    /// 408/429 are the exceptions, and 5xx is retried because Blinko surfaces
    /// transient database and AI-provider failures as `INTERNAL_SERVER_ERROR`.
    var isRetryable: Bool {
        switch self {
        case .transport, .timedOut:
            return true
        case .server(let statusCode, _, _):
            return statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
        case .invalidURL, .notConfigured, .unauthorized, .forbidden,
             .notFound, .validation, .decoding, .cancelled:
            return false
        }
    }

    /// Builds the right case from a status code and decoded body.
    static func from(statusCode: Int, body: APIErrorBody?) -> APIError {
        let message = body?.message
        switch statusCode {
        case 401:
            return .unauthorized(message: message)
        case 403:
            return .forbidden(message: message)
        case 404:
            return .notFound(message: message)
        case 400 where body?.issues?.isEmpty == false:
            return .validation(
                message: message ?? "Invalid request",
                detail: body?.validationDetail
            )
        default:
            return .server(statusCode: statusCode, message: message, code: body?.code)
        }
    }
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The server address isn't valid."
        case .notConfigured:
            return "No Blinko server is configured yet."
        case .unauthorized(let message):
            return message ?? "Your session has expired. Please sign in again."
        case .forbidden(let message):
            return message ?? "You don't have permission to do that."
        case .notFound(let message):
            return message ?? "That item no longer exists."
        case .validation(let message, let detail):
            return detail.map { "\(message) (\($0))" } ?? message
        case .server(let statusCode, let message, _):
            return message ?? "The server returned an error (\(statusCode))."
        case .decoding:
            return "The server sent a response the app couldn't read."
        case .transport:
            return "Couldn't reach the server. Check your connection."
        case .cancelled:
            return "The request was cancelled."
        case .timedOut:
            return "The server stopped responding. Check your connection."
        }
    }
}
