// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarklensCore",
    platforms: [
        .macOS(.v14),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "MarklensCore", targets: ["MarklensCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.6.0"),
    ],
    targets: [
        .target(
            name: "MarklensCore",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ],
            resources: [
                .copy("Resources/Web"),
            ]
        ),
        .testTarget(
            name: "MarklensCoreTests",
            dependencies: ["MarklensCore"]
        ),
    ]
)
