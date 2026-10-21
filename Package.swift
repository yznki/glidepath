// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "glidepath",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "glidepath", targets: ["Glidepath"]),
    ],
    targets: [
        .executableTarget(name: "Glidepath", path: "Sources/Glidepath"),
        .testTarget(name: "GlidepathTests", dependencies: ["Glidepath"], path: "Tests/GlidepathTests"),
    ]
)
