import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let wallpaper = WallpaperManager()
    private var statusItem: NSStatusItem?
    /// Set by the first `show`, so a file opened at launch wins over the saved one.
    private var hasRequestedFile = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        wallpaper.scaling = Preferences.scaling
        wallpaper.sharpPixels = Preferences.sharpPixels
        wallpaper.isPausedByUser = Preferences.isPaused
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "Tidepaper")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item

        // A file opened at launch (Finder, `open -a`) takes precedence over the saved one.
        if !hasRequestedFile, let url = fileFromCommandLine() ?? Preferences.currentFile {
            show(url)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let url = urls.first { show(url) }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let hasWallpaper = wallpaper.currentFile != nil
        menu.removeAllItems()

        if let file = wallpaper.currentFile {
            let current = NSMenuItem(title: file.lastPathComponent, action: nil, keyEquivalent: "")
            current.isEnabled = false
            menu.addItem(current)
            menu.addItem(.separator())
        }

        menu.addItem(item("Choose Wallpaper…", #selector(chooseFile), key: "o"))
        menu.addItem(recentFilesItem())
        menu.addItem(.separator())
        menu.addItem(scalingItem())
        menu.addItem(item("Sharp Pixels", #selector(toggleSharpPixels), checked: wallpaper.sharpPixels))
        menu.addItem(.separator())
        menu.addItem(item(
            wallpaper.isPausedByUser ? "Resume" : "Pause", #selector(togglePause), key: "p",
            enabled: hasWallpaper))
        menu.addItem(item("Show in Finder", #selector(showInFinder), enabled: hasWallpaper))
        menu.addItem(item("Remove Wallpaper", #selector(removeWallpaper), enabled: hasWallpaper))
        menu.addItem(.separator())
        menu.addItem(item(
            "Launch at Login", #selector(toggleLaunchAtLogin),
            checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit Tidepaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func recentFilesItem() -> NSMenuItem {
        let recentFiles = Preferences.recentFiles
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for url in recentFiles {
            let isCurrent = url.standardizedFileURL == wallpaper.currentFile?.standardizedFileURL
            let entry = item(url.lastPathComponent, #selector(openRecentFile(_:)), checked: isCurrent)
            entry.representedObject = url
            entry.toolTip = url.path
            submenu.addItem(entry)
        }
        let parent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        parent.isEnabled = !recentFiles.isEmpty
        return parent
    }

    private func scalingItem() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        for mode in ScalingMode.allCases {
            let entry = item(mode.title, #selector(chooseScaling(_:)), checked: mode == wallpaper.scaling)
            entry.representedObject = mode
            submenu.addItem(entry)
        }
        let parent = NSMenuItem(title: "Scaling", action: nil, keyEquivalent: "")
        parent.submenu = submenu
        return parent
    }

    private func item(
        _ title: String, _ action: Selector, key: String = "", checked: Bool = false, enabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }

    // MARK: Actions

    @objc private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = WallpaperContent.supportedTypes
        panel.message = "Choose a video, or an animated GIF, PNG or WebP, to use as your wallpaper."
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            show(url)
        }
    }

    @objc private func openRecentFile(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { show(url) }
    }

    @objc private func chooseScaling(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? ScalingMode else { return }
        wallpaper.scaling = mode
        Preferences.scaling = mode
    }

    @objc private func toggleSharpPixels() {
        wallpaper.sharpPixels.toggle()
        Preferences.sharpPixels = wallpaper.sharpPixels
    }

    @objc private func togglePause() {
        wallpaper.isPausedByUser.toggle()
        Preferences.isPaused = wallpaper.isPausedByUser
    }

    @objc private func showInFinder() {
        if let url = wallpaper.currentFile {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func removeWallpaper() {
        wallpaper.clear()
        Preferences.currentFile = nil
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            presentError(error)
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    // MARK: Helpers

    private func show(_ url: URL) {
        hasRequestedFile = true
        Task {
            do {
                try await wallpaper.show(url)
                Preferences.currentFile = url
                Preferences.addRecentFile(url)
            } catch is CancellationError {
                // Replaced by another file while loading.
            } catch {
                presentError(error)
            }
        }
    }

    private func presentError(_ error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        NSAlert(error: error).runModal()
    }

    /// Lets `swift run Tidepaper path/to/file.gif` and similar show a file directly.
    private func fileFromCommandLine() -> URL? {
        CommandLine.arguments.dropFirst()
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
