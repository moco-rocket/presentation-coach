// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PresentationCoach",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PresentationContracts", targets: ["PresentationContracts"]),
        .library(name: "PresentationCapture", targets: ["PresentationCapture"]),
        .library(name: "PresentationFeedback", targets: ["PresentationFeedback"]),
        .library(name: "PresentationOverlay", targets: ["PresentationOverlay"]),
        .executable(name: "PresentationApp", targets: ["PresentationApp"])
    ],
    targets: [
        .target(name: "PresentationContracts"),
        .target(
            name: "PresentationCapture",
            dependencies: ["PresentationContracts"]
        ),
        .target(
            name: "PresentationFeedback",
            dependencies: ["PresentationContracts"]
        ),
        .target(
            name: "PresentationOverlay",
            dependencies: ["PresentationContracts"],
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "PresentationApp",
            dependencies: [
                "PresentationContracts",
                "PresentationCapture",
                "PresentationFeedback",
                "PresentationOverlay"
            ]
        ),
        .testTarget(
            name: "PresentationContractsTests",
            dependencies: ["PresentationContracts"]
        ),
        .testTarget(
            name: "PresentationCaptureTests",
            dependencies: ["PresentationCapture", "PresentationContracts"]
        ),
        .testTarget(
            name: "PresentationFeedbackTests",
            dependencies: ["PresentationFeedback", "PresentationContracts"]
        ),
        .testTarget(
            name: "PresentationOverlayTests",
            dependencies: ["PresentationOverlay", "PresentationContracts"]
        ),
        .testTarget(
            name: "PresentationIntegrationTests",
            dependencies: [
                "PresentationContracts",
                "PresentationCapture",
                "PresentationFeedback"
            ]
        )
    ]
)
