// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftHttpClient",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SwiftHttpClient",
            targets: ["SwiftHttpClient"]
        )
    ],
    targets: [
        .target(
            name: "SwiftHttpClient",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftHttpClientTests",
            dependencies: ["SwiftHttpClient"]
        ),
    ]
)
