// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "review-radar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "review-radar", targets: ["ReviewRadar"]),
    ],
    targets: [
        .executableTarget(name: "ReviewRadar", path: "Sources/ReviewRadar"),
        .testTarget(name: "ReviewRadarTests", dependencies: ["ReviewRadar"], path: "Tests/ReviewRadarTests"),
    ]
)
