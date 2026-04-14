// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StreamPlayer",
    platforms: [.macOS(.v26), .iOS(.v26)],
    targets: [
        .executableTarget(name: "StreamPlayer")
    ]
)
