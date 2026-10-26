// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlidepathPrototype",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "Glidepath",
            path: "Sources/Glidepath",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
