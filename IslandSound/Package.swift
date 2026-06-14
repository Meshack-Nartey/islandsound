// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "IslandSound",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "IslandSound",
            path: "Sources/IslandSound",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "IslandSoundTests",
            dependencies: ["IslandSound"],
            path: "Tests/IslandSoundTests"
        )
    ]
)
