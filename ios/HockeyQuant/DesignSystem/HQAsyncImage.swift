import SwiftUI

/// Drop-in replacement for `AsyncImage`, backed by `ImageCache`.
///
/// Same call shape as the phase-based `AsyncImage` initialiser so migrating a
/// site is a rename plus a `size:`. That size is required rather than inferred:
/// the cache downsamples at decode time and needs to know the target before it
/// has a layout, and every call site already fixes its frame anyway.
struct HQAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let size: CGSize
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var loadedKey: String?

    init(url: URL?,
         size: CGSize,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.size = size
        self.content = content
        self.placeholder = placeholder
    }

    /// Square convenience — most call sites are square avatars/thumbnails.
    init(url: URL?,
         side: CGFloat,
         @ViewBuilder content: @escaping (Image) -> Content,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.init(url: url, size: CGSize(width: side, height: side),
                  content: content, placeholder: placeholder)
    }

    var body: some View {
        Group {
            if let image {
                content(Image(uiImage: image))
            } else {
                placeholder()
            }
        }
        // Keyed on the URL so a recycled row swaps images instead of keeping
        // the previous player's face while the new one loads.
        .task(id: url?.absoluteString) { await load() }
    }

    private func load() async {
        guard let url else { return }
        if loadedKey == url.absoluteString, image != nil { return }
        image = nil
        let loaded = await ImageCache.shared.image(for: url, size: size, scale: displayScale)
        guard !Task.isCancelled else { return }
        image = loaded
        loadedKey = url.absoluteString
    }
}
