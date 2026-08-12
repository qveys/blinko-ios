import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The note editor, used for both create and edit.
///
/// Blinko has no separate title column — the first line of the markdown body
/// *is* the title (see `Note.displayTitle`), so the editor is a single
/// markdown text area rather than title + body fields. That matches the web
/// composer's basic expectations: plain markdown source in, rendering on the
/// read screen.
///
/// Failure UX: failed saves and failed uploads keep the draft in the editor and
/// offer Retry — nothing the user typed is lost. Cancelling with unsaved text or
/// staged attachments asks before discarding.
struct NoteEditorView: View {
    @StateObject private var viewModel: NoteEditorViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var confirmDiscard = false
    @State private var pickerItem: PhotosPickerItem?
    @FocusState private var editorFocused: Bool

    /// - Parameters:
    ///   - note: the note to edit, or `nil` to create a new one.
    ///   - onSaved: receives the server's copy after a successful save.
    init(
        noteService: any NoteServiceProtocol,
        attachmentService: any AttachmentServiceProtocol = MockAttachmentService(),
        note: Note? = nil,
        onSaved: @escaping (Note) -> Void = { _ in }
    ) {
        _viewModel = StateObject(
            wrappedValue: NoteEditorViewModel(
                noteService: noteService,
                attachmentService: attachmentService,
                note: note,
                onSaved: onSaved
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TextEditor(text: $viewModel.content)
                .font(.body.monospaced())
                .autocorrectionDisabled(false)
                .focused($editorFocused)
                .padding(.horizontal, 12)
                .overlay(alignment: .topLeading) {
                    if viewModel.content.isEmpty {
                        Text("Write in markdown — the first line becomes the title.")
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 17)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                    }
                }

            if !viewModel.attachments.isEmpty || viewModel.attachmentHint != nil {
                attachmentTray
                    .padding(.horizontal)
                    .padding(.bottom, 10)
            }
        }
        .navigationTitle(isEditing ? "Edit Note" : "New Note")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: cancel)
                    .disabled(viewModel.isSaving)
            }
            ToolbarItem(placement: .topBarTrailing) {
                PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                    Label("Attach image", systemImage: "photo.badge.plus")
                }
                .disabled(viewModel.isSaving)
                .accessibilityLabel("Attach image")
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button("Save") {
                        Task { await saveAndDismiss() }
                    }
                    .disabled(!viewModel.canSave)
                    .accessibilityLabel("Save note")
                }
            }
        }
        .confirmationDialog(
            "Discard this draft?",
            isPresented: $confirmDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive, action: dismiss.callAsFunction)
            Button("Keep Editing", role: .cancel) {}
        }
        .alert("Couldn't save note", isPresented: $viewModel.showError) {
            Button("Retry") { Task { await saveAndDismiss() } }
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(viewModel.errorMessage)\n\nYour draft is preserved.")
        }
        .alert("Session expired", isPresented: $viewModel.requiresReauthentication) {
            Button("Sign In Again") {
                NotificationCenter.default.post(name: .requiresReauthentication, object: nil)
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage)
        }
        .onAppear { editorFocused = true }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await attach(item) }
        }
    }

    private var attachmentTray: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let hint = viewModel.attachmentHint {
                Label(hint, systemImage: viewModel.isUploadingAttachment ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(viewModel.isUploadingAttachment ? .secondary : .orange)
            }

            ForEach(viewModel.attachments) { attachment in
                HStack(spacing: 10) {
                    statusIcon(for: attachment.state)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(statusText(for: attachment))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if attachment.canRetry {
                        Button("Retry") { Task { await viewModel.retryAttachment(id: attachment.id) } }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Button(removeTitle(for: attachment.state), role: .destructive) {
                        viewModel.removeAttachment(id: attachment.id)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for state: NoteEditorViewModel.AttachmentState) -> some View {
        switch state {
        case .uploading:
            ProgressView()
        case .uploaded:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func statusText(for attachment: NoteEditorViewModel.AttachmentDraft) -> String {
        switch attachment.state {
        case .uploading:
            return "Uploading…"
        case .uploaded:
            return "Ready to attach · \(ByteCountFormatter.string(fromByteCount: Int64(attachment.byteCount), countStyle: .file))"
        case .failed(let message):
            return "Upload failed: \(message)"
        }
    }

    private func removeTitle(for state: NoteEditorViewModel.AttachmentState) -> String {
        if case .uploading = state { return "Cancel" }
        return "Remove"
    }

    private var isEditing: Bool {
        if case .edit = viewModel.mode { return true }
        return false
    }

    private func cancel() {
        if viewModel.hasUnsavedChanges {
            confirmDiscard = true
        } else {
            dismiss()
        }
    }

    private func saveAndDismiss() async {
        if await viewModel.save() {
            dismiss()
        }
    }

    private func attach(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            await viewModel.attachImage(data: Data(), filename: "photo", mimeType: "application/octet-stream")
            return
        }
        let contentType = item.supportedContentTypes.first { $0.conforms(to: .image) }
        let ext = contentType?.preferredFilenameExtension ?? "jpg"
        await viewModel.attachImage(
            data: data,
            filename: "photo.\(ext)",
            mimeType: contentType?.preferredMIMEType ?? "image/jpeg"
        )
    }
}

#if DEBUG
#Preview("Create") {
    NavigationStack {
        NoteEditorView(noteService: MockNoteService())
    }
}

#Preview("Edit") {
    let base = Date(timeIntervalSince1970: 1_725_000_000)
    let note = Note(
        id: 1,
        content: "# Quarter plan\n\nShip the notes list before the freeze.",
        createdAt: base,
        updatedAt: base
    )
    return NavigationStack {
        NoteEditorView(noteService: MockNoteService(notes: [note]), note: note)
    }
}
#endif
