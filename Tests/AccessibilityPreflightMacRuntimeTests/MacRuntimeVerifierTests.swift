import XCTest
@testable import AccessibilityPreflightMacRuntime
import AccessibilityPreflightBuild

final class MacRuntimeVerifierTests: XCTestCase {
    func testReturnsAssistedCheckWhenNoWindowSnapshotExists() async throws {
        let result = try await MacRuntimeVerifier(
            targetResolver: { _, _ in
                ResolvedBuildTarget(
                    projectName: "DemoApp.xcodeproj",
                    projectPath: "/tmp/Project/DemoApp.xcodeproj",
                    schemeName: "DemoApp",
                    buildableName: "DemoApp.app"
                )
            },
            builder: { _, _ in
                BuildResult(
                    buildPath: "/tmp/Derived/DemoApp.app",
                    executablePath: "/tmp/Derived/DemoApp.app/Contents/MacOS/DemoApp",
                    bundleIdentifier: "com.demo.app",
                    scheme: "DemoApp"
                )
            },
            launcher: { buildResult in
                MacLaunchResult(processIdentifiers: ["456"], launchDetail: "open request accepted")
            }
        ).verify(projectRoot: "/tmp/Project", appName: "DemoApp")

        XCTAssertEqual(result.assistedChecks.first, "Verify VoiceOver rotor order in the primary window.")
    }

    func testEmitsProvenFindingWhenMacAppLaunchSucceeds() async throws {
        let verifier = MacRuntimeVerifier(
            targetResolver: { projectRoot, appName in
                XCTAssertEqual(projectRoot, "/tmp/Project")
                XCTAssertEqual(appName, "DemoApp")
                return ResolvedBuildTarget(
                    projectName: "DemoApp.xcodeproj",
                    projectPath: "/tmp/Project/DemoApp.xcodeproj",
                    schemeName: "DemoApp",
                    buildableName: "DemoApp.app"
                )
            },
            builder: { target, destination in
                XCTAssertEqual(target.schemeName, "DemoApp")
                XCTAssertEqual(destination, "platform=macOS")
                return BuildResult(
                    buildPath: "/tmp/Derived/DemoApp.app",
                    executablePath: "/tmp/Derived/DemoApp.app/Contents/MacOS/DemoApp",
                    bundleIdentifier: "com.demo.app",
                    scheme: "DemoApp"
                )
            },
            launcher: { buildResult in
                XCTAssertEqual(buildResult.buildPath, "/tmp/Derived/DemoApp.app")
                return MacLaunchResult(
                    processIdentifiers: ["456"],
                    launchDetail: "open request accepted"
                )
            }
        )

        let result = try await verifier.verify(projectRoot: "/tmp/Project", appName: "DemoApp")

        XCTAssertTrue(result.findings.contains(where: {
            $0.confidence == .proven &&
            $0.title == "macOS app launch succeeded" &&
            $0.evidence.contains("bundle_id=com.demo.app") &&
            $0.evidence.contains("pids=456")
        }))
    }
}
