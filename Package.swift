// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cappuccino",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Cappuccino", path: "Sources/Cappuccino")
    ]
)
