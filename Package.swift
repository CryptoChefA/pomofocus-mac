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
            path: "Sources/PomofocusWidget",
            // Link it as an app extension with the system's extension entry point, as Xcode
            // does. Without it the widget starts, finds no extension context and quits, so
            // it never shows in the widget gallery.
            swiftSettings: [.unsafeFlags(["-application-extension"])],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-Xlinker", "-application_extension"])]
        )
    ]
)
