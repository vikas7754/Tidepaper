import Foundation
import ImageIO

enum AnimatedImageError: LocalizedError {
    case unreadable(URL)
    case noFrames(URL)

    var errorDescription: String? {
        switch self {
        case .unreadable(let url): "“\(url.lastPathComponent)” isn’t an image Tidepaper can read."
        case .noFrames(let url): "“\(url.lastPathComponent)” doesn’t contain any frames."
        }
    }
}

/// An animated GIF, PNG or WebP (or a still image) read with ImageIO.
///
/// Only the header and per-frame timing are read up front; Core Animation decodes the pixels.
/// Marked `@unchecked Sendable` because its state is immutable after `init` and
/// `CGImageSource` is safe to read from any thread.
final class AnimatedImage: @unchecked Sendable {
    struct Frame {
        let image: CGImage
        let delay: TimeInterval
    }

    /// What browsers use for frames with a missing or near-zero delay. Many GIFs rely on it.
    private static let defaultDelay: TimeInterval = 0.1

    let url: URL
    let frameCount: Int
    let delays: [TimeInterval]
    let pixelWidth: Int
    let pixelHeight: Int
    private let source: CGImageSource

    /// Memory needed to keep every frame decoded as 32-bit RGBA.
    var decodedByteCount: Int { pixelWidth * pixelHeight * 4 * frameCount }

    init(url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw AnimatedImageError.unreadable(url)
        }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { throw AnimatedImageError.noFrames(url) }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        self.url = url
        self.source = source
        frameCount = count
        pixelWidth = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        pixelHeight = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        delays = (0..<count).map { Self.delay(in: source, at: $0) }
    }

    /// Returns one frame, composited onto the previous ones by ImageIO, still undecoded.
    ///
    /// Core Animation decodes it when committing it to a layer, straight into the display's format
    /// and color space. That is cheaper than decoding it ourselves: Core Animation would then
    /// color-convert every pixel on the CPU (or, for an ImageIO-cached image, decode it again).
    func frame(at index: Int) -> CGImage? {
        CGImageSourceCreateImageAtIndex(source, index, [kCGImageSourceShouldCache: false] as CFDictionary)
    }

    /// Every frame ImageIO can read, with its delay.
    func allFrames() -> [Frame] {
        (0..<frameCount).compactMap { index in
            frame(at: index).map { Frame(image: $0, delay: delays[index]) }
        }
    }

    private static func delay(in source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return defaultDelay
        }
        let formats: [(container: CFString, unclamped: CFString, clamped: CFString)] = [
            (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
        ]
        for format in formats {
            guard let info = properties[format.container] as? [CFString: Any] else { continue }
            let delay = ((info[format.unclamped] ?? info[format.clamped]) as? NSNumber)?.doubleValue ?? 0
            return delay > 0.011 ? delay : defaultDelay
        }
        return defaultDelay
    }
}
