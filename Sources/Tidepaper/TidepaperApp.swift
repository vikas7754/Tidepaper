import AppKit

@main
@MainActor
enum TidepaperApp {
    // NSApplication holds its delegate weakly.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        // Menu-bar only, also when run unbundled via `swift run`.
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
