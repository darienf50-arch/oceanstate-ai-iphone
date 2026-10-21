// swift-tools-version: 5.9
import PackageDescription

// Portable request/history tests; the production app remains an iOS Xcode target.
let package = Package(
    name: "OceanStateClientCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "OceanStateAI", path: "OceanStateAI",
                exclude: ["App.swift", "Capture.swift", "MessageView.swift", "Projects.swift", "Store.swift", "VisualFixture.swift", "Assets.xcassets"],
                sources: ["Models.swift", "API.swift"]),
        .testTarget(name: "OceanStateTests", dependencies: ["OceanStateAI"], path: "Tests")
    ]
)
