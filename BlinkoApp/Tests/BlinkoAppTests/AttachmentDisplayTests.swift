import XCTest
@testable import BlinkoApp

/// Attachment display mapping: image-vs-file classification, name/size/icon
/// derivation, and the image/file split on `Note`.
final class AttachmentDisplayTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_725_000_000)

    private func makeAttachment(
        id: Int = 1,
        name: String = "photo.png",
        path: String = "/api/file/photo.png",
        size: Int64 = 20_480,
        type: String = "image/png",
        sortOrder: Int = 0
    ) -> Attachment {
        Attachment(
            id: id, name: name, path: path, size: size, type: type,
            sortOrder: sortOrder, createdAt: base, updatedAt: base
        )
    }

    // MARK: Classification

    func testMimeTypeClassifiesImage() {
        XCTAssertTrue(makeAttachment(type: "image/png").rendersAsImage)
        XCTAssertTrue(makeAttachment(type: "image/webp").rendersAsImage)
        XCTAssertFalse(makeAttachment(name: "doc.pdf", type: "application/pdf").rendersAsImage)
    }

    func testEmptyMimeTypeFallsBackToExtension() {
        // The server leaves `type` empty when detection fails — the file
        // extension should still classify the attachment.
        XCTAssertTrue(makeAttachment(name: "photo.HEIC", type: "").rendersAsImage)
        XCTAssertTrue(makeAttachment(name: "scan.jpeg", type: "").rendersAsImage)
        XCTAssertFalse(makeAttachment(name: "notes.pdf", type: "").rendersAsImage)
        XCTAssertFalse(makeAttachment(name: "archive", type: "").rendersAsImage)
    }

    func testNonImageMimeTypeWinsOverImageExtension() {
        // A detected MIME type is authoritative even when the name looks
        // like an image.
        XCTAssertFalse(makeAttachment(name: "photo.png.zip", type: "application/zip").rendersAsImage)
    }

    // MARK: Display name

    func testDisplayNamePrefersName() {
        XCTAssertEqual(makeAttachment(name: "holiday.png").displayName, "holiday.png")
    }

    func testDisplayNameFallsBackToPathComponent() {
        // Upload responses carry no `name` (API-CONTRACTS §5).
        let attachment = makeAttachment(name: "", path: "/api/file/1712345678-photo.png")
        XCTAssertEqual(attachment.displayName, "1712345678-photo.png")
    }

    func testDisplayNameFallsBackToPlaceholderWhenPathIsEmpty() {
        XCTAssertEqual(makeAttachment(name: "", path: "").displayName, "Attachment")
    }

    // MARK: Size

    func testFormattedSizeIsHumanReadable() {
        XCTAssertFalse(makeAttachment(size: 20_480).formattedSize.isEmpty)
    }

    func testUnknownSizeFormatsAsEmpty() {
        XCTAssertEqual(makeAttachment(size: 0).formattedSize, "")
    }

    // MARK: Icon

    func testIconMatchesType() {
        XCTAssertEqual(makeAttachment(name: "doc.pdf", type: "application/pdf").iconSystemName, "doc.richtext")
        XCTAssertEqual(makeAttachment(name: "a.zip", type: "application/zip").iconSystemName, "archivebox")
        XCTAssertEqual(makeAttachment(name: "song.mp3", type: "audio/mpeg").iconSystemName, "waveform")
        XCTAssertEqual(makeAttachment(name: "clip.mp4", type: "video/mp4").iconSystemName, "film")
        // Unknown type falls back to the extension, then to a generic doc.
        XCTAssertEqual(makeAttachment(name: "notes.md", type: "").iconSystemName, "doc.plaintext")
        XCTAssertEqual(makeAttachment(name: "data.bin", type: "").iconSystemName, "doc")
    }

    // MARK: URL resolution

    func testURLResolvesAgainstServerBase() {
        let attachment = makeAttachment(path: "/api/file/photo.png")
        let url = attachment.url(relativeTo: URL(string: "https://blinko.example.com:1111")!)
        XCTAssertEqual(url?.absoluteString, "https://blinko.example.com:1111/api/file/photo.png")
    }

    // MARK: Note-level split

    func testNoteSplitsImagesFromFilesAndSortsBySortOrder() {
        let image2 = makeAttachment(id: 1, name: "b.png", sortOrder: 2)
        let image1 = makeAttachment(id: 2, name: "a.png", sortOrder: 1)
        let file = makeAttachment(id: 3, name: "doc.pdf", type: "application/pdf")
        let note = Note(
            id: 1, content: "", createdAt: base, updatedAt: base,
            attachments: [image2, file, image1]
        )

        XCTAssertEqual(note.imageAttachments.map(\.id), [2, 1])
        XCTAssertEqual(note.fileAttachments.map(\.id), [3])
    }
}
