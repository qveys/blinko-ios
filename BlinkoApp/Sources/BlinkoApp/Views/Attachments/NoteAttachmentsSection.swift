import QuickLook
import SwiftUI

/// The attachments block of the note detail view: full-width images with
/// tap-to-view-full-screen, then non-image files as tappable rows that open
/// a QuickLook preview.
///
/// Files are previewed via `.quickLookPreview`, which needs a local file URL;
/// the loader downloads to a temp file on first tap (spinner on the row while
/// it fetches). A failed fetch — e.g. offline with a cold cache — shows an
/// alert and leaves the row usable for retry.
struct NoteAttachmentsSection: View {
    let note: Note

    @Environment(\.attachmentLoader) private var loader

    @State private var fullScreenImage: Attachment?
    @State private var quickLookURL: URL?
    @State private var loadingFileID: Int?
    @State private var fileError: String?
    @State private var showFileError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(note.imageAttachments) { attachment in
                AttachmentImageView(attachment: attachment, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 120, maxHeight: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture { fullScreenImage = attachment }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the image full screen")
            }

            ForEach(note.fileAttachments) { attachment in
                Button {
                    openFile(attachment)
                } label: {
                    AttachmentFileRow(
                        attachment: attachment,
                        isLoading: loadingFileID == attachment.id
                    )
                }
                .buttonStyle(.plain)
                .disabled(loadingFileID != nil)
            }
        }
        .fullScreenCover(item: $fullScreenImage) { attachment in
            AttachmentImageViewer(attachment: attachment)
        }
        .quickLookPreview($quickLookURL)
        .alert("Couldn't open attachment", isPresented: $showFileError) {
            Button("OK", role: .cancel) { fileError = nil }
        } message: {
            Text(fileError ?? "")
        }
    }

    private func openFile(_ attachment: Attachment) {
        guard let loader else {
            fileError = "Attachments are unavailable right now."
            showFileError = true
            return
        }
        loadingFileID = attachment.id
        Task {
            defer { loadingFileID = nil }
            do {
                quickLookURL = try await loader.localFileURL(for: attachment)
            } catch {
                fileError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
                showFileError = true
            }
        }
    }
}
