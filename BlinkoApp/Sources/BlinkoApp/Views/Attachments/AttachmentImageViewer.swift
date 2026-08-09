import SwiftUI

/// Full-screen presentation of one image attachment: dark backdrop,
/// pinch-to-zoom with double-tap toggle, drag-to-pan while zoomed.
///
/// Deliberately simple — the acceptance bar is "simple zoomable
/// presentation", not a full photo browser. One image per presentation; the
/// detail view presents the tapped attachment.
struct AttachmentImageViewer: View {
    let attachment: Attachment

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var steadyZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero

    private static let maxZoom: CGFloat = 4

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                AttachmentImageView(attachment: attachment, contentMode: .fit)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(zoom)
                    .offset(offset)
                    .gesture(magnification.simultaneously(with: pan))
                    .onTapGesture(count: 2) { toggleZoom() }
            }
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(attachment.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                zoom = min(max(steadyZoom * value, 1), Self.maxZoom)
            }
            .onEnded { _ in
                steadyZoom = zoom
                if zoom <= 1 { resetPosition() }
            }
    }

    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard zoom > 1 else { return }
                offset = CGSize(
                    width: steadyOffset.width + value.translation.width,
                    height: steadyOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                steadyOffset = offset
            }
    }

    private func toggleZoom() {
        withAnimation(.snappy) {
            if zoom > 1 {
                resetPosition()
            } else {
                zoom = 2
                steadyZoom = 2
            }
        }
    }

    private func resetPosition() {
        zoom = 1
        steadyZoom = 1
        offset = .zero
        steadyOffset = .zero
    }
}
