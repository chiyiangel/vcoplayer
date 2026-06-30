// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "vcoplayer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "vcoplayer", targets: ["vcoplayer"]),
        .executable(name: "vcoplayerBackendTests", targets: ["vcoplayerBackendTests"])
    ],
    dependencies: [
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "VCOPlayerCore",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "HummingbirdRouter", package: "hummingbird")
            ],
            path: "Sources/VCOPlayerCore"
        ),
        .executableTarget(
            name: "vcoplayer",
            dependencies: [
                .byName(name: "VCOPlayerCore")
            ],
            path: "Sources/vcoplayer"
        ),
        .executableTarget(
            name: "vcoplayerBackendTests",
            dependencies: [
                .byName(name: "VCOPlayerCore"),
                .product(name: "HummingbirdTesting", package: "hummingbird")
            ],
            path: "Tests/vcoplayerBackendTests"
        )
    ]
)
