// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MTPKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MTPKit", targets: ["MTPKit"]),
    ],
    targets: [
        .systemLibrary(
            name: "CLibMTP",
            pkgConfig: "libmtp",
            providers: [.brew(["libmtp"])]
        ),
        .target(
            name: "MTPKit",
            dependencies: ["CLibMTP"]
        ),
        .executableTarget(
            name: "MTPKitTests",
            dependencies: ["MTPKit"],
            path: "Tests/MTPKitTests"
        ),
    ]
)
