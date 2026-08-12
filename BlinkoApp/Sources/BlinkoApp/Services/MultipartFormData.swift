import Foundation

/// Builds a `multipart/form-data` request body.
///
/// Blinko's `file/upload` route is the only endpoint that takes multipart
/// input, so this covers exactly what that route's busboy parser reads: named
/// file parts and plain text fields. Parts are appended in call order.
struct MultipartFormData {
    /// Boundary marker, unique per request so a file containing a previous
    /// boundary string cannot break the framing.
    let boundary: String

    private var body = Data()

    init(boundary: String = "blinko.ios.\(UUID().uuidString)") {
        self.boundary = boundary
    }

    /// Value for the `Content-Type` header, boundary included.
    var contentType: String {
        "multipart/form-data; boundary=\(boundary)"
    }

    /// Appends a file part.
    ///
    /// The filename lands in `Content-Disposition`; the server derives the
    /// stored name from it. Quotes and newlines are stripped rather than
    /// escaped — busboy does not undo RFC 2047 encoding, and a mangled-but-safe
    /// name beats a broken part header.
    mutating func appendFile(
        fieldName: String,
        filename: String,
        mimeType: String,
        data: Data
    ) {
        let safeFilename = filename
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(safeFilename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        appendString("\r\n")
    }

    /// Appends a plain text field part.
    mutating func appendField(name: String, value: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    /// The complete body, closing boundary included.
    func encoded() -> Data {
        var data = body
        data.append(Data("--\(boundary)--\r\n".utf8))
        return data
    }

    private mutating func appendString(_ string: String) {
        body.append(Data(string.utf8))
    }
}
