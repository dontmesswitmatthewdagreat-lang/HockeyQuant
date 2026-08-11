import Foundation
import ImageIO
import UIKit

/// Two-tier image cache with downsampling, in front of every remote image.
///
/// `AsyncImage` refetches and re-decodes on every appearance, so scrolling a
/// feed back and forth re-downloads the same headshots and decodes them at full
/// source resolution — a 1000px portrait costs the same memory in a 44pt row as
/// it does in a hero. The marquee is the worst case: it renders two copies of
/// every image inside a `TimelineView(.animation)`.
///
/// Downsampling happens at decode time via ImageIO, so the full-size bitmap is
/// never materialised. Results are keyed by URL *and* target size, because the
/// same player appears at 38pt in a draft row and 210pt in a hero.
actor ImageCache {
    static let shared = ImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let directory: URL
    private var inFlight: [String: Task<UIImage?, Never>] = [:]

    private init() {
        memory.countLimit = 200
        memory.totalCostLimit = 64 * 1024 * 1024      // ~64MB ceiling
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("HQImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Cached, downsampled image for `url` at `size` points.
    ///
    /// `scale` must be passed in from the view's `\.displayScale` — reading
    /// `UIScreen.main.scale` here would be a main-actor hop from inside the
    /// actor, which strict concurrency rejects outright.
    func image(for url: URL, size: CGSize, scale: CGFloat) async -> UIImage? {
        let key = Self.key(url, size, scale)

        if let hit = memory.object(forKey: key as NSString) { return hit }

        // Coalesce: a feed can ask for the same headshot from several rows in
        // the same frame, and without this each one starts its own download.
        if let running = inFlight[key] { return await running.value }

        let task = Task<UIImage?, Never> { [directory] in
            let file = directory.appendingPathComponent(key)
            if let data = try? Data(contentsOf: file),
               let image = Self.decode(data, size: size, scale: scale) {
                return image
            }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let image = Self.decode(data, size: size, scale: scale) else { return nil }
            try? data.write(to: file)     // cache the source, re-decode per size
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            memory.setObject(image, forKey: key as NSString, cost: cost)
        }
        return image
    }

    /// Decode straight to the size we'll draw at — never materialise the full bitmap.
    private static func decode(_ data: Data, size: CGSize, scale: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let maxPixels = max(size.width, size.height) * max(1, scale)
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cg, scale: scale, orientation: .up)
    }

    private static func key(_ url: URL, _ size: CGSize, _ scale: CGFloat) -> String {
        var hasher = Hasher()
        hasher.combine(url.absoluteString)
        hasher.combine(Int(size.width))
        hasher.combine(Int(size.height))
        hasher.combine(Int(scale))
        // Unsigned + radix 36 keeps it short and filename-safe.
        return String(UInt(bitPattern: hasher.finalize()), radix: 36)
    }
}
