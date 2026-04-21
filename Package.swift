// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AccessibilityPreflight",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "accessibility-preflight", targets: ["AccessibilityPreflightCLI"])
    ],
    targets: [
        .target(name: "AccessibilityPreflightCore"),
        .target(name: "AccessibilityPreflightReport", dependencies: ["AccessibilityPreflightCore"]),
        .target(name: "AccessibilityPreflightStatic", dependencies: ["AccessibilityPreflightCore", "AccessibilityPreflightReport"]),
        .target(name: "AccessibilityPreflightBuild", dependencies: ["AccessibilityPreflightCore", "AccessibilityPreflightReport"]),
        .target(name: "AccessibilityPreflightIOSRuntime", dependencies: ["AccessibilityPreflightCore", "AccessibilityPreflightReport", "AccessibilityPreflightBuild"]),
        .target(name: "AccessibilityPreflightMacRuntime", dependencies: ["AccessibilityPreflightCore", "AccessibilityPreflightReport", "AccessibilityPreflightBuild"]),
        .executableTarget(
            name: "AccessibilityPreflightCLI",
            dependencies: [
                "AccessibilityPreflightCore",
                "AccessibilityPreflightReport",
                "AccessibilityPreflightStatic",
                "AccessibilityPreflightBuild",
                "AccessibilityPreflightIOSRuntime",
                "AccessibilityPreflightMacRuntime"
            ]
        ),
        .testTarget(
            name: "AccessibilityPreflightCoreTests",
            dependencies: ["AccessibilityPreflightCore"]
        ),
        .testTarget(
            name: "AccessibilityPreflightReportTests",
            dependencies: ["AccessibilityPreflightReport", "AccessibilityPreflightCore"]
        ),
        .testTarget(
            name: "AccessibilityPreflightBuildTests",
            dependencies: ["AccessibilityPreflightBuild", "AccessibilityPreflightCore"]
        ),
        .testTarget(
            name: "AccessibilityPreflightMacRuntimeTests",
            dependencies: ["AccessibilityPreflightMacRuntime"]
        ),
        .testTarget(
            name: "AccessibilityPreflightIOSRuntimeTests",
            dependencies: ["AccessibilityPreflightIOSRuntime"]
        ),
        .testTarget(
            name: "AccessibilityPreflightStaticTests",
            dependencies: ["AccessibilityPreflightStatic", "AccessibilityPreflightReport", "AccessibilityPreflightCore"]
        ),
        .testTarget(
            name: "AccessibilityPreflightCLITests",
            dependencies: ["AccessibilityPreflightCLI", "AccessibilityPreflightReport", "AccessibilityPreflightCore"]
        )
    ]
)
