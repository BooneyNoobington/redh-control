// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RedhKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "RedhKit", targets: ["RedhKit"]),
        .library(name: "RedhUI", targets: ["RedhUI"]),
    ],
    targets: [
        .target(name: "RedhKit"),
        .target(name: "RedhUI", dependencies: ["RedhKit"]),
        .testTarget(
            name: "RedhKitTests",
            dependencies: ["RedhKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
