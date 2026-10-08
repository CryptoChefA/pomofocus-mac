// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Pomofocus",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Pomofocus", targets: ["PomodoroNonna"]),
        .executable(name: "PomofocusWidgetExtension", targets: ["PomofocusWidget"])
    ],
    targets: [
        .target(
            name: "PomofocusShared",
            path: "Sources/PomofocusShared"
        ),
        .executableTarget(
            name: "PomodoroNonna",
            dependencies: ["PomofocusShared"],
            path: "Sources/PomodoroNonna"
        ),
        .executableTarget(
            name: "PomofocusWidget",
            dependencies: ["PomofocusShared"],
            path: "Sources/PomofocusWidget"
        )
    ]
)
