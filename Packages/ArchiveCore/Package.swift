// swift-tools-version: 6.0
import PackageDescription

// Everything in here is plain Swift plus SQLite, so it builds and tests on Linux
// as well as on Apple platforms. Anything that needs Vision, PDFKit, SwiftUI or
// the camera lives in the app target and reaches this package through protocols.
let package = Package(
    name: "ArchiveCore",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "ArchiveCore", targets: ["ArchiveCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.9.0"),
    ],
    targets: [
        .target(
            name: "ArchiveCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "ArchiveCoreTests",
            dependencies: ["ArchiveCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
