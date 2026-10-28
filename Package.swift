// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pyororong",
    platforms: [.macOS(.v12)],
    products: [
        .library(name: "TableConverterCore", targets: ["TableConverterCore"]),
        .library(name: "TableConverterMac", targets: ["TableConverterMac"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3"),
    ],
    targets: [
        .target(
            name: "TableConverterCore",
            dependencies: [.product(name: "SwiftSoup", package: "SwiftSoup")]
        ),
        .target(name: "TableConverterMac", dependencies: ["TableConverterCore"]),
        .testTarget(
            name: "TableConverterCoreTests",
            dependencies: ["TableConverterCore", .product(name: "SwiftSoup", package: "SwiftSoup")],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "TableConverterMacTests", dependencies: ["TableConverterMac"]),
    ]
)
