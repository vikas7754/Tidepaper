import AppKit

/// Shows the current animation or video on every display, one `WallpaperWindow` each,
/// and pauses it whenever nobody could see it.
@MainActor
final class WallpaperManager: NSObject {
    private let framePlayer = FramePlayer()
    private let videoPlayer = VideoPlayer()
    private let systemWallpaper = SystemWallpaper()
    private var windows: [CGDirectDisplayID: WallpaperWindow] = [:]
    private var screensAreAsleep = false
    /// Bumped on every `show`/`clear` so a file that finishes loading after being replaced is dropped.
    private var loadRequest = 0
    private var currentContent: WallpaperContent?

    private(set) var currentFile: URL?

    var isPausedByUser = false {
        didSet { updatePlayback() }
    }

    var scaling = ScalingMode.fill {
        didSet {
            windows.values.forEach(applyAppearance(to:))
            systemWallpaper.scaling = scaling
        }
    }

    /// Whether the macOS wallpaper, which the lock screen shows, follows Tidepaper's as a still frame.
    var matchesLockScreen = true {
        didSet {
            guard matchesLockScreen != oldValue else { return }
            updateSystemWallpaper()
        }
    }

    var sharpPixels = false {
        didSet { windows.values.forEach(applyAppearance(to:)) }
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(
            self, selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification, object: nil)
    }

    /// Puts `url` on every display. Throws if it can't be shown, or `CancellationError`
    /// if another file was shown or the wallpaper removed while this one was loading.
    func show(_ url: URL) async throws {
        loadRequest += 1
        let request = loadRequest
        let content = try await WallpaperContent(url: url)
        guard request == loadRequest else { throw CancellationError() }

        currentFile = url
        syncWindowsWithScreens()
        switch content {
        case .image(let image):
            videoPlayer.stop()
            framePlayer.play(image)
        case .video(let asset):
            framePlayer.stop()
            videoPlayer.play(asset)
        }
        currentContent = content
        updateSystemWallpaper()
    }

    /// Takes the wallpaper down, uncovering the system one.
    func clear() {
        loadRequest += 1
        currentFile = nil
        currentContent = nil
        framePlayer.stop()
        videoPlayer.stop()
        syncWindowsWithScreens()
        updateSystemWallpaper()
    }

    private func updateSystemWallpaper() {
        if matchesLockScreen, let currentContent {
            systemWallpaper.match(currentContent)
        } else {
            systemWallpaper.restore()
        }
    }

    /// One window per connected display while there is something to show, none otherwise.
    private func syncWindowsWithScreens() {
        var stale = windows
        windows = [:]
        if currentFile != nil {
            for screen in NSScreen.screens {
                guard let id = screen.displayID else { continue }
                let window = stale.removeValue(forKey: id) ?? makeWindow(for: screen)
                window.setFrame(screen.frame, display: true)
                windows[id] = window
            }
        }
        stale.values.forEach(remove)
        updatePlayback()
    }

    private func makeWindow(for screen: NSScreen) -> WallpaperWindow {
        let window = WallpaperWindow(screen: screen)
        applyAppearance(to: window)
        framePlayer.attach(window.imageLayer)
        videoPlayer.attach(window.videoLayer)
        NotificationCenter.default.addObserver(
            self, selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification, object: window)
        window.orderFront(nil)
        return window
    }

    private func remove(_ window: WallpaperWindow) {
        NotificationCenter.default.removeObserver(
            self, name: NSWindow.didChangeOcclusionStateNotification, object: window)
        framePlayer.detach(window.imageLayer)
        videoPlayer.detach(window.videoLayer)
        window.orderOut(nil)
    }

    private func applyAppearance(to window: WallpaperWindow) {
        window.imageLayer.contentsGravity = scaling.contentsGravity
        window.imageLayer.magnificationFilter = sharpPixels ? .nearest : .linear
        window.videoLayer.videoGravity = scaling.videoGravity
    }

    /// Paused by the user, displays asleep, or every window covered (e.g. full-screen apps).
    private func updatePlayback() {
        let anyVisible = windows.values.contains { $0.occlusionState.contains(.visible) }
        let isPaused = isPausedByUser || screensAreAsleep || !anyVisible
        framePlayer.isPaused = isPaused
        videoPlayer.isPaused = isPaused
    }

    @objc private func screensChanged() {
        syncWindowsWithScreens()
    }

    @objc private func screensDidSleep() {
        screensAreAsleep = true
        updatePlayback()
    }

    @objc private func screensDidWake() {
        screensAreAsleep = false
        updatePlayback()
    }

    @objc private func occlusionChanged() {
        updatePlayback()
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}
