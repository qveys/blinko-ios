import SwiftUI

/// One non-image attachment: type icon, filename, size.
///
/// The row itself is dumb — the parent owns the tap, because cards ignore it
/// (navigation wins) while detail opens a QuickLook preview.
struct AttachmentFileRow: View {
    let attachment: Attachment
    /// Shown while the parent is fetching the file for preview.
    var isLoading = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.iconSystemName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.displayName)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !attachment.formattedSize.isEmpty {
                    Text(attachment.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            if isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = ["File attachment", attachment.displayName]
        if !attachment.formattedSize.isEmpty { parts.append(attachment.formattedSize) }
        return parts.joined(separator: ", ")
    }
}
