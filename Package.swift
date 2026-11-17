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
  dependencies: [.package(name: "HarborSDK", path: "HarborIntegration/SDK")],
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
      dependencies: ["EucranteCore", .product(name: "HarborKit", package: "HarborSDK")],
      resources: [.copy("Resources/PagePicker.js")],
      linkerSettings: [
        .linkedFramework("UserNotifications"),
        .linkedFramework("WebKit"),
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
    .testTarget(
      name: "EucranteAppTests",
      dependencies: ["EucranteApp"]
    ),
  ]
)
