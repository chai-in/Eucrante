// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "HarborSDK",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "HarborKit", targets: ["HarborKit"]),
        .executable(name: "harbor-release", targets: ["HarborRelease"])
    ],
    targets: [
        .systemLibrary(name: "CArchive"),
        .target(name: "HarborKit"),
        .target(name: "HarborCore", dependencies: ["HarborKit", "CArchive"]),
        .executableTarget(name: "HarborRelease", dependencies: ["HarborCore"])
    ],
    swiftLanguageVersions: [.v5]
)
