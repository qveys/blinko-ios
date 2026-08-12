import Foundation

/// Fetches attachment bytes from `/api/file/*` with the bearer token attached.
///
/// Kept as a protocol so views can be previewed and tested without a network.
protocol AttachmentAssetLoading: Sendable {
    /// Raw bytes of the attachment, for inline image rendering.
    func data(for attachment: Attachment) async throws -> Data
    /// A local file URL with the attachment's filename, for QuickLook and the
    /// share sheet — both need an on-disk file, not bytes.
    func localFileURL(for attachment: Attachment) async throws -> URL
}

/// `URLSession`-backed loader for attachment content.
///
/// Plain `AsyncImage` cannot be used for attachments: `/api/file/*` requires
/// the same `Authorization: Bearer` header as the rest of the API and would
/// answer 401 without it. This loader mirrors `URLSessionHTTPClient`'s auth
/// handling for the file routes.
///
/// Caching, per the offline philosophy (docs/ARCHITECTURE.md):
/// - an in-memory `NSCache` absorbs list scrolling and cell reuse;
/// - requests use `.returnCacheDataElseLoad`, so anything `URLCache` has on
///   disk still renders when the network is gone. A cache miss offline throws,
///   and the view shows a placeholder — never a crash.
///
/// An `actor` so concurrent cells requesting the same image share one in-flight
/// task instead of racing duplicate downloads.
actor AttachmentAssetLoader: AttachmentAssetLoading {
    /// Origin of the Blinko instance; attachment paths are server-relative.
    private let serverURL: URL
    private let session: URLSession
    private let tokenProvider: (any TokenProviding)?
    private let memoryCache = NSCache<NSURL, NSData>()
    private var inFlight: [URL: Task<Data, any Error>] = [:]

    init(
        serverURL: URL,
        session: URLSession = .shared,
        tokenProvider: (any TokenProviding)? = nil
    ) {
        self.serverURL = serverURL
        self.session = session
        self.tokenProvider = tokenProvider
        // ~24 MB of decoded-size-agnostic raw bytes; NSCache evicts under
        // memory pressure on its own.
        memoryCache.totalCostLimit = 24 * 1024 * 1024
    }

    func data(for attachment: Attachment) async throws -> Data {
        guard let url = attachment.url(relativeTo: serverURL) else {
            throw APIError.invalidURL
        }
        if let cached = memoryCache.object(forKey: url as NSURL) {
            return cached as Data
        }
        if let task = inFlight[url] {
            return try await task.value
        }
        let task = Task { [session, tokenProvider] in
            try await Self.fetch(url, session: session, tokenProvider: tokenProvider)
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let data = try await task.value
        memoryCache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }

    func localFileURL(for attachment: Attachment) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("blinko-attachments", isDirectory: true)
            .appendingPathComponent(String(attachment.id), isDirectory: true)
        // Keyed by id so distinct attachments sharing a filename don't collide,
        // while the leaf keeps the real name — QuickLook titles the preview
        // with it and picks the renderer from its extension.
        let fileURL = directory.appendingPathComponent(attachment.displayName)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return fileURL
        }
        let data = try await data(for: attachment)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    private static func fetch(
        _ url: URL,
        session: URLSession,
        tokenProvider: (any TokenProviding)?
    ) async throws -> Data {
        var request = URLRequest(url: url)
        // Serve from URLCache when the server is unreachable; hit the network
        // only on a disk-cache miss.
        request.cachePolicy = .returnCacheDataElseLoad
        if let token = await tokenProvider?.token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = try? JSONDecoder.blinko.decode(APIErrorBody.self, from: data)
            throw APIError.from(statusCode: httpResponse.statusCode, body: body)
        }
        return data
    }
}
