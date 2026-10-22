import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Keeps the macOS wallpaper in step with Tidepaper's. The lock screen and login window only
/// ever show the system wallpaper, so it's set to a still frame of the current file; the user's
/// own wallpaper is put back when Tidepaper's is removed.
///
/// macOS keeps a wallpaper per Space, so each Space is brought in line when it becomes active.
@MainActor
final class SystemWallpaper: NSObject {
    private static let defaultPicture = "/System/Library/CoreServices/DefaultDesktop.heic"

    /// ~/Library/Application Support/Tidepaper, where the still frames live.
    private let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Tidepaper", isDirectory: true)
    private var still: URL?
    private var stillIsVideo = false
    /// Bumped on every `match`/`restore` so a still that finishes after being replaced is dropped.
    private var request = 0

    var scaling = ScalingMode.fill {
        didSet { if still != nil { apply(force: true) } }
    }

    override init() {
        super.init()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(spaceOrScreensChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(spaceOrScreensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    /// Sets the system wallpaper on every display to the first frame of `content`.
    func match(_ content: WallpaperContent) {
        request += 1
        let request = self.request
        let isVideo = if case .video = content { true } else { false }
        // A new name each time: macOS caches wallpapers by file URL.
        let url = folder.appendingPathComponent("Still-\(UUID().uuidString).\(isVideo ? "jpg" : "png")")
        Task {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try await Self.writeFirstFrame(of: content, to: url)
            } catch {
                return  // Best effort: the animated wallpaper plays either way.
            }
            guard request == self.request else {
                try? FileManager.default.removeItem(at: url)
                return
            }
            still = url
            stillIsVideo = isVideo
            apply(force: true)
            removeStills(except: url)
        }
    }

    /// Puts the user's own wallpaper back wherever one of Tidepaper's stills is showing.
    func restore() {
        request += 1
        still = nil
        apply(force: false)
        removeStills(except: nil)
    }

    @objc private func spaceOrScreensChanged() {
        apply(force: false)
    }

    /// Shows the still on every display of the current Space, remembering what it replaces;
    /// with no still, puts the remembered wallpaper back where a stale still is showing.
    private func apply(force: Bool) {
        let workspace = NSWorkspace.shared
        var originals = Preferences.originalDesktopPictures
        for screen in NSScreen.screens {
            guard let id = screen.displayID.map(String.init) else { continue }
            let current = workspace.desktopImageURL(for: screen)
            let showsStill = current.map(isStill) ?? false
            if let still {
                guard force || current?.path != still.path else { continue }
                if let current, !showsStill { originals[id] = current.path }
                try? workspace.setDesktopImageURL(still, for: screen, options: desktopImageOptions)
            } else if showsStill {
                let original = originals[id] ?? originals.values.first ?? Self.defaultPicture
                try? workspace.setDesktopImageURL(URL(fileURLWithPath: original), for: screen, options: [:])
            }
        }
        Preferences.originalDesktopPictures = originals
    }

    /// The system's equivalent of the current scaling mode.
    private var desktopImageOptions: [NSWorkspace.DesktopImageOptionKey: Any] {
        let proportional = NSImageScaling.scaleProportionallyUpOrDown.rawValue
        switch scaling {
        case .fill:
            return [.imageScaling: proportional, .allowClipping: true]
        case .fit:
            return [.imageScaling: proportional, .allowClipping: false, .fillColor: NSColor.black]
        case .stretch:
            return [.imageScaling: NSImageScaling.scaleAxesIndependently.rawValue, .allowClipping: true]
        case .center:
            // Videos have no actual-size mode, so Center fits them like Fit to Screen.
            let mode = stillIsVideo ? proportional : NSImageScaling.scaleNone.rawValue
            return [.imageScaling: mode, .allowClipping: false, .fillColor: NSColor.black]
        }
    }

    private func isStill(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path == folder.standardizedFileURL.path
    }

    private func removeStills(except kept: URL?) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix("Still-") && file.path != kept?.path {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private nonisolated static func writeFirstFrame(of content: WallpaperContent, to url: URL) async throws {
        let image: CGImage
        switch content {
        case .image(let animated):
            guard let frame = animated.frame(at: 0) else { throw CocoaError(.fileReadCorruptFile) }
            image = frame
        case .video(let asset):
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            image = try await generator.image(at: .zero).image
        }
        let type: UTType = url.pathExtension == "jpg" ? .jpeg : .png
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }
}
