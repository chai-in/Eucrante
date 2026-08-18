// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "Eucrante",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .library(name: "EucranteCore", targets: ["EucranteCore"]),
    .executable(name: "Eucrante", targets: ["EucranteApp"]),
    .executable(name: "EucranteCoreChecks", targets: ["EucranteCoreChecks"]),
  ],
  targets: [
    .target(
      name: "EucranteCore",
      linkerSettings: [
        .linkedFramework("Security")
      ]
    ),
    .executableTarget(
      name: "EucranteApp",
      dependencies: ["EucranteCore"]
    ),
    .executableTarget(
      name: "EucranteCoreChecks",
      dependencies: ["EucranteCore"]
    ),
    .testTarget(
      name: "EucranteCoreTests",
      dependencies: ["EucranteCore"]
    ),
  ]
)
