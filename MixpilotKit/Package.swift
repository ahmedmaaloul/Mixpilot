// swift-tools-version: 6.2
import PackageDescription

/// Mixpilot's engine, without UI: process discovery, grouping, settings and (from M2) the
/// Core Audio taps that change each app's volume.
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
        // Core Audio HAL access.
        .target(
            name: "MixpilotAudio",
            dependencies: ["MixpilotCore"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "MixpilotCoreTests",
            dependencies: ["MixpilotCore"],
            swiftSettings: [
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
    ]
)
