import AVFoundation
import QuartzCore

enum ScalingMode: String, CaseIterable {
    case fill, fit, stretch, center

    var title: String {
        switch self {
        case .fill: "Fill Screen"
        case .fit: "Fit to Screen"
        case .stretch: "Stretch to Fill"
        case .center: "Center"
        }
    }

    var contentsGravity: CALayerContentsGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit: .resizeAspect
        case .stretch: .resize
        case .center: .center
        }
    }

    /// Videos have no actual-size mode, so Center fits them like Fit to Screen.
    var videoGravity: AVLayerVideoGravity {
        switch self {
        case .fill: .resizeAspectFill
        case .fit, .center: .resizeAspect
        case .stretch: .resize
        }
    }
}

/// Settings kept in UserDefaults. Files are stored as bookmarks, so they survive being moved or renamed.
enum Preferences {
    private static let maxRecentFiles = 8
    private static var defaults: UserDefaults { .standard }

    static var scaling: ScalingMode {
        get { defaults.string(forKey: "scaling").flatMap(ScalingMode.init(rawValue:)) ?? .fill }
        set { defaults.set(newValue.rawValue, forKey: "scaling") }
    }

    static var sharpPixels: Bool {
        get { defaults.bool(forKey: "sharpPixels") }
        set { defaults.set(newValue, forKey: "sharpPixels") }
    }

    static var isPaused: Bool {
        get { defaults.bool(forKey: "paused") }
        set { defaults.set(newValue, forKey: "paused") }
    }

    /// On unless turned off.
    static var matchesLockScreen: Bool {
        get { defaults.object(forKey: "matchesLockScreen") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "matchesLockScreen") }
    }

    /// The user's own macOS wallpaper per display ID, put back when Tidepaper's is removed.
    static var originalDesktopPictures: [String: String] {
        get { defaults.dictionary(forKey: "originalDesktopPictures") as? [String: String] ?? [:] }
        set { defaults.set(newValue, forKey: "originalDesktopPictures") }
    }

    static var currentFile: URL? {
        get { defaults.data(forKey: "currentFile").flatMap(url(fromBookmark:)) }
        set { defaults.set(newValue.flatMap(bookmark(for:)), forKey: "currentFile") }
    }

    /// Most recently used first. Files that no longer exist are left out.
    static var recentFiles: [URL] {
        get { (defaults.array(forKey: "recentFiles") as? [Data] ?? []).compactMap(url(fromBookmark:)) }
        set { defaults.set(newValue.prefix(maxRecentFiles).compactMap(bookmark(for:)), forKey: "recentFiles") }
    }

    static func addRecentFile(_ url: URL) {
        recentFiles = [url] + recentFiles.filter { $0.standardizedFileURL != url.standardizedFileURL }
    }

    private static func bookmark(for url: URL) -> Data? {
        try? url.bookmarkData()
    }

    private static func url(fromBookmark data: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: .withoutUI, bookmarkDataIsStale: &isStale)
    }
}
