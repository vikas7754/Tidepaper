import AVFoundation
import UniformTypeIdentifiers

/// A file the wallpaper can show, checked and ready to play.
enum WallpaperContent {
    case image(AnimatedImage)
    case video(AVURLAsset)

    static let supportedTypes: [UTType] = [.gif, .png, .webP, .movie]

    enum LoadError: LocalizedError {
        case unplayableVideo(URL)

        var errorDescription: String? {
            switch self {
            case .unplayableVideo(let url): "“\(url.lastPathComponent)” isn’t a video Tidepaper can play."
            }
        }
    }

    init(url: URL) async throws {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
            ?? UTType(filenameExtension: url.pathExtension)
        guard type?.conforms(to: .movie) == true else {
            self = .image(try AnimatedImage(url: url))
            return
        }

        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable),
              try await !asset.loadTracks(withMediaType: .video).isEmpty
        else { throw LoadError.unplayableVideo(url) }
        self = .video(asset)
    }
}
