// swift-tools-version: 6.2
import PackageDescription

/// Mixpilot's engine, without UI: process discovery, grouping, settings and the Core Audio taps
/// that change each app's volume.
let package = Package(
    name: "MixpilotKit",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "MixpilotCore", targets: ["MixpilotCore"]),
        .library(name: "MixpilotAudio", targets: ["MixpilotAudio"]),
    ],
    targets: [
        // Pure logic, no Core Audio: everything here is unit tested.
        .target(
            name: "MixpilotCore",
            swiftSettings: [
                // Same concurrency model as the app target (Xcode "Approachable Concurrency"):
                // nonisolated async functions run on the caller's actor.
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        // The audio thread's code, in C so it is provably real-time safe.
        .target(
            name: "MixpilotRender",
            cSettings: [.unsafeFlags(["-Wall", "-Wextra", "-Werror"])],
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        // Core Audio HAL access: process discovery, taps, aggregate devices.
        .target(
            name: "MixpilotAudio",
            dependencies: ["MixpilotCore", "MixpilotRender"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ],
            linkerSettings: [.linkedFramework("CoreAudio")]
        ),
        .testTarget(
            name: "MixpilotCoreTests",
            dependencies: ["MixpilotCore"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "MixpilotRenderTests",
            dependencies: ["MixpilotRender"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
