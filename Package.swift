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
        .linkedFramework("Security"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("AudioToolbox"),
        .linkedFramework("CoreMedia"),
      ]
    ),
    .executableTarget(
      name: "EucranteApp",
      dependencies: ["EucranteCore"],
      linkerSettings: [
        .linkedFramework("UserNotifications")
      ]
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
