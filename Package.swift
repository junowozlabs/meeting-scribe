// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeetingScribe", targets: ["MeetingScribe"])
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Security")
            ]
        ),
        .testTarget(name: "MeetingScribeTests", dependencies: ["MeetingScribe"])
    ]
)
