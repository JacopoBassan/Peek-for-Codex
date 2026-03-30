// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PeekForCodex",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "PeekForCodex", targets: ["PeekForCodex"]),
    ],
    targets: [
        .executableTarget(
            name: "PeekForCodex",
            path: "Sources/PeekForCodex"
        ),
    ]
)
