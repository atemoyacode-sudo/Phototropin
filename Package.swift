// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PomeVision",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "ScreenshotAnswerCore", targets: ["ScreenshotAnswerCore"]),
        .executable(name: "PomeVision", targets: ["ScreenshotAnswerApp"]),
        .executable(name: "pome-vision-cli", targets: ["ScreenshotAnswerCLI"]),
    ],
    targets: [
        .target(
            name: "ScreenshotAnswerCore",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Vision"),
            ]
        ),
        .executableTarget(
            name: "ScreenshotAnswerApp",
            dependencies: ["ScreenshotAnswerCore"],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Speech"),
            ]
        ),
        .executableTarget(
            name: "ScreenshotAnswerCLI",
            dependencies: ["ScreenshotAnswerCore"]
        ),
        .testTarget(
            name: "ScreenshotAnswerCoreTests",
            dependencies: ["ScreenshotAnswerCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
