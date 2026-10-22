import AppKit
import AVFoundation

/// A borderless, click-through window covering one display at desktop level:
/// above the system wallpaper, below the desktop icons, on every Space.
final class WallpaperWindow: NSWindow {
    let imageLayer = CALayer()
    let videoLayer = AVPlayerLayer()

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        hasShadow = false
        backgroundColor = .black
        animationBehavior = .none

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        // Only one of the two shows something at a time.
        for layer in [imageLayer, videoLayer] {
            layer.frame = view.bounds
            layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            // Swap frames and follow resizes instantly instead of cross-fading.
            layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
            view.layer?.addSublayer(layer)
        }
        contentView = view
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    // Cover the whole display, including the area under the menu bar.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
