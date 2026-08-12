import Foundation

/// In-memory `NoteServiceProtocol` backed by ``APIFixtures``.
///
/// Lets UI work proceed against realistic data before a server is reachable,
/// and gives tests a seam that does not touch the network. State mutates the
/// way the real service would — trashing removes from the list, upserting
/// replaces in place — so a screen driven by this behaves like the real one.
///
/// An `actor` because the protocol is `Sendable` and callers hit it from tasks.
actor MockNoteService: NoteServiceProtocol {
    private var notes: [Note]
    /// When set, every call throws this instead of returning. For error paths.
    private let error: (any Error)?
    /// When set, only *write* calls throw. Lets a test load a list successfully
    /// and then fail the mutation — which is the only way to exercise
    /// optimistic-update rollback.
    private let writeError: (any Error)?
    /// Artificial latency, for exercising loading states in previews.
    private let delay: Duration

    /// - Parameters:
    ///   - notes: seed data. Defaults to the fixture list.
    ///   - error: when non-nil, every call throws it.
    ///   - writeError: when non-nil, only mutating calls throw it.
    ///   - delay: artificial latency per call.
    init(
        notes: [Note] = APIFixtures.sampleNotes,
        error: (any Error)? = nil,
        writeError: (any Error)? = nil,
        delay: Duration = .zero
    ) {
        self.notes = notes
        self.error = error
        self.writeError = writeError
        self.delay = delay
    }

    /// Empty list, for testing empty states.
    static var empty: MockNoteService { MockNoteService(notes: []) }

    /// Always fails, for testing error states.
    static func failing(_ error: any Error = APIError.unauthorized(message: nil)) -> MockNoteService {
        MockNoteService(error: error)
    }

    private func preflight() async throws {
        if delay != .zero { try await Task.sleep(for: delay) }
        if let error { throw error }
    }

    /// Preflight for mutating calls, which can be failed independently of reads.
    private func preflightWrite() async throws {
        try await preflight()
        if let writeError { throw writeError }
    }

    private func index(of id: Int) throws -> Int {
        guard let index = notes.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound(message: "No note with id \(id).")
        }
        return index
    }

    func fetchNotes(_ request: NoteListRequest) async throws -> [Note] {
        try await preflight()

        // Mirror the server's filtering closely enough that pagination and
        // empty states behave realistically in previews.
        var results = notes.filter { note in
            if note.isRecycle != request.isRecycle { return false }
            if let isArchived = request.isArchived, note.isArchived != isArchived { return false }
            if request.type != NoteType.any, note.type.rawValue != request.type { return false }
            if let tagId = request.tagId, !note.tags.contains(where: { $0.id == tagId }) { return false }
            if !request.searchText.isEmpty,
               !note.content.localizedCaseInsensitiveContains(request.searchText) { return false }
            if request.withoutTag, !note.tags.isEmpty { return false }
            if request.withFile, note.attachments.isEmpty { return false }
            return true
        }

        // Pinned first, then by recency — the ordering the list screen expects.
        results.sort { lhs, rhs in
            if lhs.isTop != rhs.isTop { return lhs.isTop }
            return request.orderBy == .descending
                ? lhs.updatedAt > rhs.updatedAt
                : lhs.updatedAt < rhs.updatedAt
        }

        // 1-based offset pagination, matching `/v1/note/list`.
        let start = max(0, (request.page - 1) * request.size)
        guard start < results.count else { return [] }
        return Array(results[start..<min(start + request.size, results.count)])
    }

    func fetchNote(id: Int) async throws -> Note {
        try await preflight()
        let position = try index(of: id)
        return notes[position]
    }

    func createNote(content: String, type: NoteType) async throws -> Note {
        try await upsert(.create(content: content, type: type))
    }

    func updateContent(id: Int, content: String) async throws -> Note {
        try await upsert(.updateContent(id: id, content: content))
    }

    func upsert(_ request: NoteUpsertRequest) async throws -> Note {
        try await preflightWrite()

        guard let id = request.id else {
            let now = Date()
            let note = Note(
                id: (notes.map(\.id).max() ?? 0) + 1,
                content: request.content ?? "",
                type: NoteType(rawValue: request.type ?? NoteType.blinko.rawValue) ?? .blinko,
                accountId: 1,
                createdAt: now,
                updatedAt: now
            )
            notes.insert(note, at: 0)
            return note
        }

        // Update: omitted fields are left untouched, as the server does.
        let position = try index(of: id)
        var note = notes[position]
        if let content = request.content { note.content = content }
        if let rawType = request.type, let type = NoteType(rawValue: rawType) { note.type = type }
        if let isTop = request.isTop { note.isTop = isTop }
        if let isArchived = request.isArchived { note.isArchived = isArchived }
        if let isRecycle = request.isRecycle { note.isRecycle = isRecycle }
        note.updatedAt = Date()
        notes[position] = note
        return note
    }

    func setTop(id: Int, isTop: Bool) async throws -> Note {
        try await upsert(.setTop(id: id, isTop: isTop))
    }

    func setArchived(id: Int, isArchived: Bool) async throws -> Note {
        try await upsert(.setArchived(id: id, isArchived: isArchived))
    }

    func trash(ids: [Int]) async throws {
        try await preflightWrite()
        setRecycled(ids: ids, isRecycle: true)
    }

    func restore(ids: [Int]) async throws {
        try await preflightWrite()
        setRecycled(ids: ids, isRecycle: false)
    }

    /// Batch endpoints ignore ids that aren't present rather than failing.
    private func setRecycled(ids: [Int], isRecycle: Bool) {
        for position in notes.indices where ids.contains(notes[position].id) {
            notes[position].isRecycle = isRecycle
        }
    }

    func delete(ids: [Int]) async throws {
        try await preflightWrite()
        notes.removeAll { ids.contains($0.id) }
    }
}

/// In-memory `TagServiceProtocol` backed by ``APIFixtures``.
actor MockTagService: TagServiceProtocol {
    private var tags: [Tag]
    private let error: (any Error)?

    init(tags: [Tag] = APIFixtures.sampleTags, error: (any Error)? = nil) {
        self.tags = tags
        self.error = error
    }

    func fetchTags() async throws -> [Tag] {
        if let error { throw error }
        return tags
    }

    func renameTag(id: Int, from oldName: String, to newName: String) async throws {
        if let error { throw error }
        guard let index = tags.firstIndex(where: { $0.id == id }) else {
            throw APIError.notFound(message: "No tag with id \(id).")
        }
        tags[index].name = newName
        tags[index].updatedAt = Date()
    }

    func deleteTag(id: Int) async throws {
        if let error { throw error }
        // Matches `delete-only-tag`: the tag goes, its notes stay. Children are
        // reparented to root rather than orphaned.
        tags.removeAll { $0.id == id }
        for index in tags.indices where tags[index].parent == id {
            tags[index].parent = 0
        }
    }
}

/// In-memory `AuthServiceProtocol`.
///
/// Accepts any non-empty credentials unless seeded with an error, so previews
/// can walk the sign-in flow without a server.
actor MockAuthService: AuthServiceProtocol {
    private let user: User
    private let error: (any Error)?

    init(
        user: User = User(
            id: 1,
            name: "alice",
            nickname: "Alice",
            image: "",
            role: "superadmin",
            loginType: "password"
        ),
        error: (any Error)? = nil
    ) {
        self.user = user
        self.error = error
    }

    func login(name: String, password: String) async throws -> User {
        if let error { throw error }
        guard !name.isEmpty, !password.isEmpty else {
            throw APIError.validation(
                message: "Invalid request",
                detail: "Name and password are required."
            )
        }
        return user
    }

    func logout() async {}
}

/// In-memory `AttachmentServiceProtocol`.
///
/// Echoes the upload back the way the server would: a timestamped,
/// space-collapsed stored name under `/api/file/`. Seed `error` to exercise
/// failure paths.
actor MockAttachmentService: AttachmentServiceProtocol {
    /// How an error seeded on this mock behaves across repeated calls.
    private enum FailureMode {
        /// Never fails.
        case none
        /// Fails every call — for asserting a terminal error state.
        case always(any Error)
        /// Fails the next `remaining` calls, then succeeds. Lets one instance
        /// exercise "upload fails → user taps Retry → it works".
        case times(remaining: Int, any Error)
    }

    private var failureMode: FailureMode
    /// Artificial latency, for observing the in-flight upload state.
    private let delay: Duration
    /// Every upload accepted so far, for asserting in tests.
    private(set) var uploads: [(filename: String, mimeType: String, byteCount: Int)] = []

    init(error: (any Error)? = nil, delay: Duration = .zero) {
        self.failureMode = error.map { .always($0) } ?? .none
        self.delay = delay
    }

    private init(failureMode: FailureMode, delay: Duration) {
        self.failureMode = failureMode
        self.delay = delay
    }

    /// Always fails, for testing error states.
    static func failing(_ error: any Error = APIError.unauthorized(message: nil)) -> MockAttachmentService {
        MockAttachmentService(error: error)
    }

    /// Fails the first `count` uploads, then succeeds. For retry paths.
    static func failingTimes(
        _ count: Int,
        _ error: any Error = APIError.transport("offline"),
        delay: Duration = .zero
    ) -> MockAttachmentService {
        MockAttachmentService(failureMode: .times(remaining: count, error), delay: delay)
    }

    func upload(data: Data, filename: String, mimeType: String) async throws -> AttachmentUploadResponse {
        if delay != .zero { try await Task.sleep(for: delay) }
        switch failureMode {
        case .none:
            break
        case .always(let error):
            throw error
        case .times(let remaining, let error):
            if remaining > 0 {
                failureMode = .times(remaining: remaining - 1, error)
                throw error
            }
        }
        uploads.append((filename, mimeType, data.count))
        // Mirror the server's renaming: spaces collapse to underscores and a
        // timestamp prefix is added on collision; the prefix alone is enough
        // for previews.
        let storedName = "1714746000-" + filename.replacingOccurrences(of: " ", with: "_")
        return AttachmentUploadResponse(
            path: "/api/file/\(storedName)",
            type: mimeType,
            size: Int64(data.count),
            name: storedName
        )
    }
}
