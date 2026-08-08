import Foundation

struct Note: Identifiable, Codable, Sendable {
    let id: Int
    let content: String
    let type: NoteType
    let isTop: Bool
    let createdAt: Date
    let updatedAt: Date

    enum NoteType: String, Codable {
        case blinko
        case note
    }
}
