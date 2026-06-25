// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .defaultIsolation(MainActor.self),
]

let package = Package(
    name: "StrandDesign",
    platforms: [.macOS(.v13), .iOS(.v16), .watchOS(.v10)],
    products: [.library(name: "StrandDesign", targets: ["StrandDesign"])],
    dependencies: [],
    targets: [
        .target(name: "StrandDesign", swiftSettings: swiftSettings),
        .testTarget(name: "StrandDesignTests", dependencies: ["StrandDesign"], swiftSettings: swiftSettings),
    ]
)
