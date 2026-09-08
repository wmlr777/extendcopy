// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExtendCopy",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ExtendCopy", targets: ["ExtendCopy"]),
        .library(name: "ExtendCopyCore", targets: ["ExtendCopyCore"]),
    ],
    targets: [
        .target(name: "ExtendCopyCore"),
        .executableTarget(
            name: "ExtendCopy",
            dependencies: ["ExtendCopyCore"]
        ),
        .testTarget(
            name: "ExtendCopyCoreTests",
            dependencies: ["ExtendCopyCore"]
        ),
    ]
)
