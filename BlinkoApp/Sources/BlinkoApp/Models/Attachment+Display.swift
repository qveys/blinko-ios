import Foundation

// MARK: - Classification

extension Attachment {
    /// File extensions treated as images when the server did not detect a MIME
    /// type. Matches the formats `UIImage` can decode from downloaded data.
    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tiff", "tif"
    ]

    /// Whether this attachment should render as an inline image.
    ///
    /// Prefers the server-detected MIME type, but falls back to the path's
    /// file extension because `type` is empty when detection failed — a
    /// `photo.png` with no MIME type should still render as a picture, not a
    /// generic file row.
    var rendersAsImage: Bool {
        if !type.isEmpty { return isImage }
        return Self.imageExtensions.contains(pathExtension.lowercased())
    }

    /// Name to show in file rows. Falls back to the path's last component
    /// because upload responses carry no `name` (see API-CONTRACTS §5).
    var displayName: String {
        if !name.isEmpty { return name }
        let component = (path as NSString).lastPathComponent
        return component.isEmpty ? "Attachment" : component
    }

    /// Human-readable size, e.g. "20 KB". Empty when the size is unknown —
    /// the row then omits the size line rather than showing "Zero KB".
    var formattedSize: String {
        guard size > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// SF Symbol for the file-row icon, keyed off MIME type first and file
    /// extension as the fallback (same precedence as ``rendersAsImage``).
    var iconSystemName: String {
        if type.hasPrefix("image/") { return "photo" }
        if type.hasPrefix("video/") { return "film" }
        if type.hasPrefix("audio/") { return "waveform" }
        switch type {
        case "application/pdf": return "doc.richtext"
        case "application/zip", "application/x-tar", "application/gzip":
            return "archivebox"
        default: break
        }
        switch pathExtension.lowercased() {
        case "pdf": return "doc.richtext"
        case "zip", "tar", "gz", "7z", "rar": return "archivebox"
        case "md", "txt", "log": return "doc.plaintext"
        case "mp4", "mov", "mkv": return "film"
        case "mp3", "m4a", "wav", "flac": return "waveform"
        default: return "doc"
        }
    }

    private var pathExtension: String {
        (displayName as NSString).pathExtension
    }
}

// MARK: - Note-level grouping

extension Note {
    /// Attachments that render as inline images, in the server's `sortOrder`.
    /// Drives the thumbnail grid on cards and the image stack in detail.
    var imageAttachments: [Attachment] {
        attachments
            .filter(\.rendersAsImage)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Everything else — rendered as name+icon file rows.
    var fileAttachments: [Attachment] {
        attachments
            .filter { !$0.rendersAsImage }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}
