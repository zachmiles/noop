// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
    name: "backfill",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../Packages/StrandImport"),
        .package(path: "../../Packages/WhoopStore"),
    ],
    targets: [
        .executableTarget(name: "backfill", dependencies: ["StrandImport", "WhoopStore"], swiftSettings: swiftSettings),
    ]
)
