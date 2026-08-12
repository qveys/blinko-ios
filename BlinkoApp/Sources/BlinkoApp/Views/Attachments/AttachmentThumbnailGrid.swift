import SwiftUI

/// Compact image grid for note cards, mirroring Blinko web's card thumbnails.
///
/// Shows at most ``maxThumbnails`` square tiles; when more images exist the
/// last tile dims under a "+N" badge. Purely decorative on the card — taps
/// fall through to the row's navigation, full-size viewing lives in detail.
struct AttachmentThumbnailGrid: View {
    let images: [Attachment]

    /// Cards cap at one row of three, like the web's dense list.
    static let maxThumbnails = 3
    private static let tileSize: CGFloat = 84
    private static let cornerRadius: CGFloat = 8

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, attachment in
                tile(for: attachment, isLast: index == visible.count - 1)
            }
        }
    }

    private var visible: [Attachment] { Array(images.prefix(Self.maxThumbnails)) }

    private var overflowCount: Int { images.count - visible.count }

    @ViewBuilder
    private func tile(for attachment: Attachment, isLast: Bool) -> some View {
        AttachmentImageView(attachment: attachment)
            .frame(width: Self.tileSize, height: Self.tileSize)
            .overlay {
                if isLast, overflowCount > 0 {
                    ZStack {
                        Color.black.opacity(0.45)
                        Text("+\(overflowCount)")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("\(overflowCount) more images")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
    }
}
