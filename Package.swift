// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tidepaper",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Tidepaper", path: "Sources/Tidepaper"),
    ]
)
