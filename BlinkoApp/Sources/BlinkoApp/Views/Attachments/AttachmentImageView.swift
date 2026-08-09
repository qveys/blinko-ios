import SwiftUI
import UIKit

// MARK: - Environment plumbing

/// The loader reaches image views through the environment rather than every
/// intermediate initializer — `MainTabView` injects the real one, previews and
/// tests inject stubs (or nothing, and get the placeholder state).
private struct AttachmentLoaderKey: EnvironmentKey {
    static let defaultValue: (any AttachmentAssetLoading)? = nil
}

extension EnvironmentValues {
    var attachmentLoader: (any AttachmentAssetLoading)? {
        get { self[AttachmentLoaderKey.self] }
        set { self[AttachmentLoaderKey.self] = newValue }
    }
}

// MARK: - Async image

/// Authenticated replacement for `AsyncImage`: loads attachment bytes through
/// ``AttachmentAssetLoading`` (which sends the bearer token — plain
/// `AsyncImage` would 401) and renders placeholder → image → failure states.
///
/// Loading rides on `.task(id:)`, so SwiftUI cancels the fetch when the cell
/// scrolls away and restarts it if the row is reused for another attachment.
/// Offline with a cold cache, the load fails and the failure state shows — a
/// broken-photo glyph, never a crash or a spinner that never resolves.
struct AttachmentImageView: View {
    let attachment: Attachment
    var contentMode: ContentMode = .fill

    @Environment(\.attachmentLoader) private var loader

    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            case .loaded(let image):
                Color.clear.overlay {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
                .clipped()
            case .failed:
                Rectangle()
                    .fill(Color.secondary.opacity(0.12))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.badge.exclamationmark")
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
        .task(id: attachment.id) {
            await load()
        }
        .accessibilityLabel(attachment.displayName.isEmpty ? "Image attachment" : attachment.displayName)
    }

    private func load() async {
        // Always restart: `.task(id:)` only re-fires when the attachment
        // changed, and the loader's memory cache makes a re-fetch of the same
        // bytes effectively free.
        phase = .loading
        guard let loader else {
            phase = .failed
            return
        }
        do {
            let data = try await loader.data(for: attachment)
            if let image = UIImage(data: data) {
                phase = .loaded(image)
            } else {
                phase = .failed
            }
        } catch APIError.cancelled {
            // Cell scrolled away — leave the placeholder; a reused row's
            // `.task(id:)` starts a fresh load.
        } catch {
            phase = .failed
        }
    }
}
