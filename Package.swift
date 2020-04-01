// swift-tools-version:5.0

import PackageDescription

let package = Package(
    name: "Witness",
    products: [
        .library(
            name: "Witness",
            targets: ["Witness"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(name: "Witness", dependencies: ["CLinuxUtils"]),
        .testTarget(
            name: "WitnessTests",
            dependencies: ["Witness"]),
        .target(name: "CLinuxUtils", dependencies: []),
    ],
    swiftLanguageVersions: [.v4, .v4_2, .v5]
)
