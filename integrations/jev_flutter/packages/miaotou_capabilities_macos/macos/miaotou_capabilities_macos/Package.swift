// swift-tools-version: 5.9
// The Swift Package Manager half of this plugin's macOS build. Flutter 3.47
// resolves macOS plugins this way; the podspec beside it is the fallback for a
// project that has not moved yet. Both list the same sources, so neither is a
// second copy of the implementation.

import PackageDescription

let package = Package(
    name: "miaotou_capabilities_macos",
    platforms: [
        // 14.0 for `SCScreenshotManager.captureImage`. See the podspec.
        .macOS("14.0")
    ],
    products: [
        .library(
            name: "miaotou-capabilities-macos",
            targets: ["miaotou_capabilities_macos"]
        )
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "miaotou_capabilities_macos",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
