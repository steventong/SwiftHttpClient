// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SwiftHttpClient",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
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
        )
    ]
)
